package com.minibrain.collegebook.APIServices;

import android.app.ActivityManager;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.media.Ringtone;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.widget.RemoteViews;

import androidx.annotation.NonNull;
import androidx.core.app.NotificationCompat;

import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;
import com.google.gson.JsonObject;
import com.minibrain.collegebook.College.CounsellorConsultationActionReceiver;
import com.minibrain.collegebook.College.IncomingCounsellorConsultationActivity;
import com.minibrain.collegebook.Model.CounsellorCallResponseModel;
import com.minibrain.collegebook.R;
import com.minibrain.collegebook.Utilities.FcmTokenHelper;

import java.util.List;
import java.util.Map;

import okhttp3.ResponseBody;
import retrofit2.Call;
import retrofit2.Callback;
import retrofit2.Response;

/**
 * Push handling for mentors (counsellor side, ported from Medshow's
 * BigDoctorFirebaseMessagingService):
 *  - COUNSELLOR_NEW_REQUEST → app open: incoming-call screen; otherwise looped ringtone +
 *    full-screen Accept/Decline notification, auto-declined after 20s,
 *  - COUNSELLOR_CALL_MISSED → stop ringing, drop the notification and close the screen,
 *  - token refresh → re-register the device for the approved counsellor.
 */
public class CollegeBookFirebaseMessagingService extends FirebaseMessagingService {

    private static final String TAG = "CollegeBookFCM";

    // Silent channel — the ring is played (looped) by startServiceRingtone(), which a one-shot
    // channel sound can't do; a channel sound as well would double-ring.
    private static final String COUNSELLOR_CHANNEL_ID = "counsellor_consultation_channel_silent_v2";
    private static final String COUNSELLOR_CHANNEL_NAME = "Incoming Counselling Sessions";
    public static final int COUNSELLOR_NOTIF_ID = 3001;
    private static final long AUTO_DECLINE_MS = 20_000;

    private static final Handler mainHandler = new Handler(Looper.getMainLooper());
    private static Runnable counsellorAutoDeclineRunnable;
    private static Ringtone serviceRingtone;

    // ---------------------------------------------------------------- token

    @Override
    public void onNewToken(@NonNull String token) {
        super.onNewToken(token);
        // Firebase rotates the token on its own schedule; the backend keeps the last one it got,
        // so push the new one or calls silently stop arriving.
        // Only for a logged-in user (RestClient.get() sends their CollegeBook token) whose
        // notifications are on — same rule as at login.
        if (!new SessionManager(this).isLoggedIn() || !FcmTokenHelper.notificationsEnabled(this)) {
            Log.d(TAG, "onNewToken: not logged in or notifications off — skipping device registration");
            return;
        }
        JsonObject payload = new JsonObject();
        FcmTokenHelper.addDeviceFields(payload, token); // registration_id + device_type
        RestClient.get().registerCounsellorDevice(payload)
                .enqueue(new Callback<ResponseBody>() {
                    @Override
                    public void onResponse(Call<ResponseBody> call, Response<ResponseBody> response) {
                        Log.d(TAG, "onNewToken: device registration code=" + response.code());
                    }

                    @Override
                    public void onFailure(Call<ResponseBody> call, Throwable t) {
                        Log.e(TAG, "onNewToken: device registration failed", t);
                    }
                });
    }

    // ---------------------------------------------------------------- messages

    @Override
    public void onMessageReceived(@NonNull RemoteMessage remoteMessage) {
        super.onMessageReceived(remoteMessage);
        Map<String, String> data = remoteMessage.getData();
        if (data.isEmpty()) {
            Log.w(TAG, "Empty data payload");
            return;
        }

        String type = data.get("type");
        String sessionId = data.get("session_id");
        String title = data.get("title");
        if ((title == null || title.isEmpty()) && remoteMessage.getNotification() != null) {
            title = remoteMessage.getNotification().getTitle();
        }

        if ("COUNSELLOR_NEW_REQUEST".equals(type)) {
            String userName = data.get("user_name");
            if (isAppInForeground()) {
                launchIncomingCounsellorActivity(sessionId, userName); // it rings itself
            } else {
                startServiceRingtone();
                showCounsellorConsultationNotification(sessionId, title, userName);
            }
        } else if ("COUNSELLOR_CALL_MISSED".equals(type)) {
            handleCounsellorCallMissed(sessionId);
        }
    }

    private void handleCounsellorCallMissed(String sessionId) {
        stopServiceRingtone();
        cancelCounsellorAutoDeclineTimer();
        NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm != null) nm.cancel(COUNSELLOR_NOTIF_ID);
        // Close the incoming-call screen if it's showing this session.
        mainHandler.post(() -> IncomingCounsellorConsultationActivity.dismissIfShowing(sessionId));
    }

    // ---------------------------------------------------------------- ringtone

    private void startServiceRingtone() {
        try {
            stopServiceRingtone();
            Uri uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE);
            serviceRingtone = RingtoneManager.getRingtone(getApplicationContext(), uri);
            if (serviceRingtone != null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) serviceRingtone.setLooping(true);
                serviceRingtone.play();
            }
        } catch (Exception e) {
            Log.e(TAG, "Ringtone error: " + e.getMessage());
        }
    }

    public static void stopServiceRingtone() {
        try {
            if (serviceRingtone != null && serviceRingtone.isPlaying()) serviceRingtone.stop();
            serviceRingtone = null;
        } catch (Exception e) {
            Log.e(TAG, "Stop ringtone error: " + e.getMessage());
        }
    }

    // ---------------------------------------------------------------- respond API

    /** Accept/reject without a screen (notification actions, auto-decline). */
    public static void callCounsellorRespondApi(Context context, String sessionId, String action) {
        Call<CounsellorCallResponseModel> call = "accept".equals(action)
                ? RestClient.get().acceptCounsellorCall(sessionId)
                : RestClient.get().rejectCounsellorCall(sessionId);
        call.enqueue(new Callback<CounsellorCallResponseModel>() {
            @Override
            public void onResponse(Call<CounsellorCallResponseModel> call, Response<CounsellorCallResponseModel> response) {
                Log.d(TAG, "respond [" + action + "] code=" + response.code());
            }

            @Override
            public void onFailure(Call<CounsellorCallResponseModel> call, Throwable t) {
                Log.e(TAG, "respond [" + action + "] failed: " + t.getMessage());
            }
        });
    }

    // ---------------------------------------------------------------- foreground check

    private boolean isAppInForeground() {
        ActivityManager am = (ActivityManager) getSystemService(Context.ACTIVITY_SERVICE);
        if (am == null) return false;
        List<ActivityManager.RunningAppProcessInfo> processes = am.getRunningAppProcesses();
        if (processes == null) return false;
        for (ActivityManager.RunningAppProcessInfo p : processes) {
            if (p.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
                    && p.processName.equals(getPackageName())) {
                return true;
            }
        }
        return false;
    }

    // ---------------------------------------------------------------- incoming screen / notification

    private void launchIncomingCounsellorActivity(String sessionId, String userName) {
        Intent intent = buildCounsellorActivityIntent(sessionId, userName);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        try {
            startActivity(intent);
        } catch (Exception e) {
            Log.e(TAG, "Launch failed: " + e.getMessage());
        }
    }

    private Intent buildCounsellorActivityIntent(String sessionId, String userName) {
        Intent intent = new Intent(this, IncomingCounsellorConsultationActivity.class);
        intent.putExtra(IncomingCounsellorConsultationActivity.EXTRA_SESSION_ID, sessionId);
        intent.putExtra(IncomingCounsellorConsultationActivity.EXTRA_USER_NAME, userName);
        intent.putExtra(IncomingCounsellorConsultationActivity.EXTRA_NOTIF_ID, COUNSELLOR_NOTIF_ID);
        return intent;
    }

    private void showCounsellorConsultationNotification(String sessionId, String title, String userName) {
        try {
            NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm == null) return;
            createCounsellorChannel(nm);

            int flags = PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE;

            Intent tapIntent = buildCounsellorActivityIntent(sessionId, userName);
            tapIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            PendingIntent tapPending = PendingIntent.getActivity(this, COUNSELLOR_NOTIF_ID, tapIntent, flags);

            PendingIntent acceptPending = PendingIntent.getBroadcast(this, COUNSELLOR_NOTIF_ID + 1,
                    CounsellorConsultationActionReceiver.intent(this, CounsellorConsultationActionReceiver.ACTION_ACCEPT, sessionId, userName),
                    flags);
            PendingIntent declinePending = PendingIntent.getBroadcast(this, COUNSELLOR_NOTIF_ID + 2,
                    CounsellorConsultationActionReceiver.intent(this, CounsellorConsultationActionReceiver.ACTION_DECLINE, sessionId, userName),
                    flags);

            String name = userName != null && !userName.isEmpty() ? userName : "A student";
            RemoteViews views = new RemoteViews(getPackageName(), R.layout.notification_consultation);
            views.setTextViewText(R.id.tv_notif_title, title != null && !title.isEmpty() ? title : "New Consultation Request");
            views.setTextViewText(R.id.tv_notif_body, name + " wants to start a video consultation.");
            views.setOnClickPendingIntent(R.id.btn_notif_accept, acceptPending);
            views.setOnClickPendingIntent(R.id.btn_notif_decline, declinePending);

            NotificationCompat.Builder builder = new NotificationCompat.Builder(this, COUNSELLOR_CHANNEL_ID)
                    .setSmallIcon(R.drawable.ic_baseline_notifications_24)
                    .setCustomBigContentView(views)
                    .setCustomContentView(views)
                    .setPriority(NotificationCompat.PRIORITY_MAX)
                    .setCategory(NotificationCompat.CATEGORY_CALL)
                    .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                    .setFullScreenIntent(tapPending, true)
                    .setVibrate(new long[]{0, 500, 300, 500, 300, 500})
                    .setAutoCancel(true)
                    .setTimeoutAfter(AUTO_DECLINE_MS)
                    .setContentIntent(tapPending);

            nm.notify(COUNSELLOR_NOTIF_ID, builder.build());
            startCounsellorAutoDeclineTimer(sessionId);
        } catch (Exception e) {
            Log.e(TAG, "Notification failed: " + e.getMessage(), e);
        }
    }

    private void startCounsellorAutoDeclineTimer(String sessionId) {
        cancelCounsellorAutoDeclineTimer();
        Context app = getApplicationContext();
        counsellorAutoDeclineRunnable = () -> {
            Log.d(TAG, "Auto-decline after 20s");
            stopServiceRingtone();
            NotificationManager nm = (NotificationManager) app.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm != null) nm.cancel(COUNSELLOR_NOTIF_ID);
            callCounsellorRespondApi(app, sessionId, "reject");
        };
        mainHandler.postDelayed(counsellorAutoDeclineRunnable, AUTO_DECLINE_MS);
    }

    public static void cancelCounsellorAutoDeclineTimer() {
        if (counsellorAutoDeclineRunnable != null) {
            mainHandler.removeCallbacks(counsellorAutoDeclineRunnable);
            counsellorAutoDeclineRunnable = null;
        }
    }

    private void createCounsellorChannel(NotificationManager nm) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        if (nm.getNotificationChannel(COUNSELLOR_CHANNEL_ID) != null) return;
        NotificationChannel channel = new NotificationChannel(
                COUNSELLOR_CHANNEL_ID, COUNSELLOR_CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH);
        channel.setDescription("Incoming counselling video request alerts");
        channel.enableVibration(true);
        channel.setVibrationPattern(new long[]{0, 500, 300, 500, 300, 500});
        channel.setSound(null, null); // the ring is played (looped) by startServiceRingtone()
        channel.setLockscreenVisibility(NotificationCompat.VISIBILITY_PUBLIC);
        channel.setShowBadge(true);
        channel.setBypassDnd(true);
        nm.createNotificationChannel(channel);
    }
}
