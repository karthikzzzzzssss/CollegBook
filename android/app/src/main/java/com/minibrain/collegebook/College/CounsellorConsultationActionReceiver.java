package com.minibrain.collegebook.College;

import android.app.NotificationManager;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.widget.Toast;

import com.minibrain.collegebook.APIServices.CollegeBookFirebaseMessagingService;
import com.minibrain.collegebook.APIServices.RestClient;
import com.minibrain.collegebook.Model.CounsellorCallResponseModel;

import retrofit2.Call;
import retrofit2.Callback;
import retrofit2.Response;

/**
 * Accept / Decline buttons on the incoming-consultation notification (ported from Medshow).
 * Accept calls the API and opens the video call; Decline only tells the backend.
 */
public class CounsellorConsultationActionReceiver extends BroadcastReceiver {

    private static final String TAG = "CounsellorReceiver";

    public static final String ACTION_ACCEPT = "com.minibrain.collegebook.COUNSELLOR_ACCEPT";
    public static final String ACTION_DECLINE = "com.minibrain.collegebook.COUNSELLOR_DECLINE";

    public static final String EXTRA_SESSION_ID = "session_id";
    public static final String EXTRA_USER_NAME = "user_name";

    public static Intent intent(Context context, String action, String sessionId, String userName) {
        return new Intent(action)
                .setClass(context, CounsellorConsultationActionReceiver.class)
                .putExtra(EXTRA_SESSION_ID, sessionId)
                .putExtra(EXTRA_USER_NAME, userName);
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        String sessionId = intent.getStringExtra(EXTRA_SESSION_ID);

        CollegeBookFirebaseMessagingService.stopServiceRingtone();
        CollegeBookFirebaseMessagingService.cancelCounsellorAutoDeclineTimer();
        NotificationManager nm = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm != null) nm.cancel(CollegeBookFirebaseMessagingService.COUNSELLOR_NOTIF_ID);

        if (ACTION_ACCEPT.equals(action)) {
            acceptAndOpenCall(context.getApplicationContext(), sessionId);
        } else if (ACTION_DECLINE.equals(action)) {
            CollegeBookFirebaseMessagingService.callCounsellorRespondApi(context, sessionId, "reject");
        }
    }

    private void acceptAndOpenCall(Context context, String sessionId) {
        RestClient.get().acceptCounsellorCall(sessionId).enqueue(new Callback<CounsellorCallResponseModel>() {
            @Override
            public void onResponse(Call<CounsellorCallResponseModel> call, Response<CounsellorCallResponseModel> response) {
                CounsellorCallResponseModel body = response.body();
                if (response.isSuccessful() && body != null && body.isStatus() && body.getData() != null) {
                    CounsellorVideoCallActivity.start(context, body.getData());
                } else {
                    Log.e(TAG, "Accept failed — code=" + response.code());
                    new Handler(Looper.getMainLooper()).post(() ->
                            Toast.makeText(context, "Couldn't join the call", Toast.LENGTH_LONG).show());
                }
            }

            @Override
            public void onFailure(Call<CounsellorCallResponseModel> call, Throwable t) {
                Log.e(TAG, "Accept failed: " + t.getMessage(), t);
                new Handler(Looper.getMainLooper()).post(() ->
                        Toast.makeText(context, "Couldn't join the call", Toast.LENGTH_LONG).show());
            }
        });
    }
}
