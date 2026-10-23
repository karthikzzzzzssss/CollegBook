package com.minibrain.collegebook.College;

import android.app.KeyguardManager;
import android.app.NotificationManager;
import android.content.Context;
import android.content.Intent;
import android.media.Ringtone;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.CountDownTimer;
import android.util.Log;
import android.view.WindowManager;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;

import com.minibrain.collegebook.APIServices.CollegeBookFirebaseMessagingService;
import com.minibrain.collegebook.APIServices.RestClient;
import com.minibrain.collegebook.Model.CounsellorCallResponseModel;
import com.minibrain.collegebook.R;

import java.lang.ref.WeakReference;

import retrofit2.Call;
import retrofit2.Callback;
import retrofit2.Response;

/**
 * Full-screen incoming consultation call for a mentor (ported from Medshow): shows over the
 * lock screen, rings, counts down 30s (then auto-declines). Accept → backend → video call.
 */
public class IncomingCounsellorConsultationActivity extends AppCompatActivity {

    private static final String TAG = "IncomingCounsellor";
    private static final int RING_SECONDS = 30;

    public static final String EXTRA_SESSION_ID = "session_id";
    public static final String EXTRA_USER_NAME = "user_name";
    public static final String EXTRA_NOTIF_ID = "notif_id";

    /** The screen currently showing, so a COUNSELLOR_CALL_MISSED push can close it. */
    private static WeakReference<IncomingCounsellorConsultationActivity> current = new WeakReference<>(null);

    private CountDownTimer countDownTimer;
    private Ringtone ringtone;

    private String sessionId;
    private String userName;
    private int notifId;
    private boolean responding = false;

    private TextView tvUserName, tvSessionType, tvTimer, btnAccept, btnDecline;
    private ProgressBar progressTimer;

    /** Called on the main thread by the FCM service when the caller hung up before we answered. */
    public static void dismissIfShowing(String missedSessionId) {
        IncomingCounsellorConsultationActivity screen = current.get();
        if (screen == null || screen.isFinishing()) return;
        if (screen.sessionId == null || screen.sessionId.equals(missedSessionId)) {
            Log.d(TAG, "Call missed (caller cancelled) → closing");
            screen.stopCountdown();
            screen.stopRingtone();
            screen.dismissNotification();
            Toast.makeText(screen, "Call missed", Toast.LENGTH_SHORT).show();
            screen.finish();
        }
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true);
            setTurnScreenOn(true);
            KeyguardManager km = (KeyguardManager) getSystemService(Context.KEYGUARD_SERVICE);
            if (km != null) km.requestDismissKeyguard(this, null);
        } else {
            getWindow().addFlags(WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
                    | WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                    | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON);
        }
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        setContentView(R.layout.activity_incoming_counsellor_consultation);
        current = new WeakReference<>(this);

        readExtras(getIntent());
        tvUserName = findViewById(R.id.tv_patient_name);
        tvSessionType = findViewById(R.id.tv_session_type);
        tvTimer = findViewById(R.id.tv_timer);
        progressTimer = findViewById(R.id.progress_timer);
        btnAccept = findViewById(R.id.btn_accept);
        btnDecline = findViewById(R.id.btn_decline);
        populateViews();

        btnAccept.setOnClickListener(v -> respond("accept"));
        btnDecline.setOnClickListener(v -> respond("reject"));

        // The service may already be ringing (app was in background) — one ring is enough.
        CollegeBookFirebaseMessagingService.stopServiceRingtone();
        CollegeBookFirebaseMessagingService.cancelCounsellorAutoDeclineTimer();
        startRingtone();
        startCountdown();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        readExtras(intent);
        populateViews();
        startCountdown();
    }

    private void readExtras(Intent intent) {
        if (intent == null) return;
        sessionId = intent.getStringExtra(EXTRA_SESSION_ID);
        userName = intent.getStringExtra(EXTRA_USER_NAME);
        notifId = intent.getIntExtra(EXTRA_NOTIF_ID, 0);
    }

    private void populateViews() {
        tvUserName.setText(userName != null && !userName.isEmpty() ? userName : "Student");
        tvSessionType.setText("🎥  Video Consultation");
    }

    // ---------------------------------------------------------------- accept / reject

    private void respond(String action) {
        if (responding) return;
        responding = true;
        stopCountdown();
        CollegeBookFirebaseMessagingService.cancelCounsellorAutoDeclineTimer();
        btnAccept.setEnabled(false);
        btnDecline.setEnabled(false);

        Call<CounsellorCallResponseModel> call = "accept".equals(action)
                ? RestClient.get().acceptCounsellorCall(sessionId)
                : RestClient.get().rejectCounsellorCall(sessionId);

        call.enqueue(new Callback<CounsellorCallResponseModel>() {
            @Override
            public void onResponse(Call<CounsellorCallResponseModel> call, Response<CounsellorCallResponseModel> response) {
                CounsellorCallResponseModel body = response.body();
                boolean ok = response.isSuccessful() && body != null && body.isStatus();
                Log.d(TAG, action + " → code=" + response.code() + " ok=" + ok);
                onResponded(action, ok ? body : null);
            }

            @Override
            public void onFailure(Call<CounsellorCallResponseModel> call, Throwable t) {
                Log.e(TAG, action + " failed: " + t.getMessage());
                onResponded(action, null);
            }
        });
    }

    private void onResponded(String action, CounsellorCallResponseModel body) {
        if (isFinishing()) return;
        responding = false;

        if ("accept".equals(action)) {
            if (body != null && body.getData() != null) {
                stopRingtone();
                dismissNotification();
                CounsellorVideoCallActivity.start(this, body.getData());
                finish();
            } else {
                // Let them try again while the caller is still waiting.
                Toast.makeText(this, "Failed to accept. Please try again.", Toast.LENGTH_SHORT).show();
                btnAccept.setEnabled(true);
                btnDecline.setEnabled(true);
                startCountdown();
            }
        } else {
            stopRingtone();
            dismissNotification();
            finish();
        }
    }

    // ---------------------------------------------------------------- ring + countdown

    private void startRingtone() {
        try {
            Uri uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE);
            ringtone = RingtoneManager.getRingtone(this, uri);
            if (ringtone != null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) ringtone.setLooping(true);
                ringtone.play();
            }
        } catch (Exception e) {
            Log.e(TAG, "Ringtone error: " + e.getMessage());
        }
    }

    private void stopRingtone() {
        try {
            if (ringtone != null && ringtone.isPlaying()) ringtone.stop();
        } catch (Exception e) {
            Log.e(TAG, "Stop ringtone error: " + e.getMessage());
        }
        CollegeBookFirebaseMessagingService.stopServiceRingtone();
    }

    private void startCountdown() {
        stopCountdown();
        progressTimer.setMax(RING_SECONDS);
        progressTimer.setProgress(RING_SECONDS);
        countDownTimer = new CountDownTimer(RING_SECONDS * 1000L, 1000) {
            @Override
            public void onTick(long ms) {
                int sec = (int) (ms / 1000);
                tvTimer.setText(sec + "s");
                progressTimer.setProgress(sec);
            }

            @Override
            public void onFinish() {
                respond("reject");
            }
        }.start();
    }

    private void stopCountdown() {
        if (countDownTimer != null) {
            countDownTimer.cancel();
            countDownTimer = null;
        }
    }

    private void dismissNotification() {
        NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm != null) {
            nm.cancel(CollegeBookFirebaseMessagingService.COUNSELLOR_NOTIF_ID);
            if (notifId != 0) nm.cancel(notifId);
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        stopCountdown();
        stopRingtone();
        if (current.get() == this) current = new WeakReference<>(null);
    }
}
