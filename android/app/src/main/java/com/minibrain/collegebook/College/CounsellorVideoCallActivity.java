package com.minibrain.collegebook.College;

import android.Manifest;
import android.app.AlertDialog;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.util.Log;
import android.view.TextureView;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Toast;

import androidx.activity.OnBackPressedCallback;
import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;

import com.google.gson.JsonObject;
import com.minibrain.collegebook.APIServices.AppConstants;
import com.minibrain.collegebook.APIServices.CounsellorCallSocketManager;
import com.minibrain.collegebook.APIServices.RestClient;
import com.minibrain.collegebook.APIServices.VideoCallForegroundService;
import com.minibrain.collegebook.Model.CounsellorCallEndResponse;
import com.minibrain.collegebook.Model.CounsellorCallResponseModel;
import com.minibrain.collegebook.R;
import com.minibrain.collegebook.Utilities.Utils;
import com.minibrain.collegebook.databinding.ActivityCounsellorVideoCallBinding;

import io.agora.rtc2.ChannelMediaOptions;
import io.agora.rtc2.Constants;
import io.agora.rtc2.IRtcEngineEventHandler;
import io.agora.rtc2.RtcEngine;
import io.agora.rtc2.video.VideoCanvas;
import retrofit2.Call;
import retrofit2.Callback;
import retrofit2.Response;

/**
 * Mentor's side of an accepted consultation (ported from Medshow): Agora video, mute / switch
 * camera / end, tap a tile to swap views. Ends on the mentor's request (end API), when the
 * student leaves, or when the call socket says the call is over (cancelled, balance gone…).
 */
public class CounsellorVideoCallActivity extends AppCompatActivity {

    private static final String TAG = "CounsellorVideoCall";
    private static final int PERMISSION_REQ_ID = 22;
    private static final String[] REQUESTED_PERMISSIONS = {Manifest.permission.RECORD_AUDIO, Manifest.permission.CAMERA};

    private static final String EXTRA_SESSION_ID = "session_id";
    private static final String EXTRA_TOKEN = "token";
    private static final String EXTRA_UID = "uid";
    private static final String EXTRA_CHANNEL = "channel_name";

    private ActivityCounsellorVideoCallBinding binding;
    private String sessionId, channelName, agoraToken;
    private int uid;

    private RtcEngine rtcEngine;
    private TextureView localTextureView, remoteTextureView;
    private boolean muted = false;
    private boolean isSwapped = false;
    private boolean isSessionEnded = false;
    private boolean isForceClosing = false;
    private CounsellorCallSocketManager socketManager;

    public static void start(Context context, CounsellorCallResponseModel.Data data) {
        Intent intent = new Intent(context, CounsellorVideoCallActivity.class)
                .putExtra(EXTRA_SESSION_ID, data.getSessionId())
                .putExtra(EXTRA_TOKEN, data.getAgoraToken())
                .putExtra(EXTRA_UID, data.getUid())
                .putExtra(EXTRA_CHANNEL, data.getChannelName())
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        context.startActivity(intent);
    }

    private final IRtcEngineEventHandler rtcEventHandler = new IRtcEngineEventHandler() {
        @Override
        public void onUserJoined(int remoteUid, int elapsed) {
            runOnUiThread(() -> {
                setupRemoteVideo(remoteUid);
            });
        }

        @Override
        public void onUserOffline(int remoteUid, int reason) {
            runOnUiThread(() -> {
                binding.remoteVideoViewContainer.removeAllViews();
                onForceClose("Session ended by the other participant.");
            });
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        binding = ActivityCounsellorVideoCallBinding.inflate(getLayoutInflater());
        setContentView(binding.getRoot());

        Bundle extra = getIntent().getExtras();
        if (extra != null) {
            sessionId = extra.getString(EXTRA_SESSION_ID);
            agoraToken = extra.getString(EXTRA_TOKEN);
            uid = extra.getInt(EXTRA_UID);
            channelName = extra.getString(EXTRA_CHANNEL);
        }

        setupSystemBars();
        binding.Back.setOnClickListener(v -> showExitCallDialog());
        getOnBackPressedDispatcher().addCallback(this, new OnBackPressedCallback(true) {
            @Override
            public void handleOnBackPressed() {
                showExitCallDialog();
            }
        });
        View.OnClickListener swap = v -> swapVideoViews();
        binding.remoteVideoViewContainer.setOnClickListener(swap);
        binding.localVideoSmallContainer.setOnClickListener(swap);

        if (checkPermissions()) joinChannel();
        else ActivityCompat.requestPermissions(this, REQUESTED_PERMISSIONS, PERMISSION_REQ_ID);
        connectCallSocket();
    }

    private void setupSystemBars() {
        getWindow().setStatusBarColor(getColor(R.color.black));
        getWindow().setNavigationBarColor(getColor(R.color.black));
        WindowCompat.getInsetsController(getWindow(), getWindow().getDecorView()).setAppearanceLightStatusBars(false);
        ViewCompat.setOnApplyWindowInsetsListener(binding.main, (v, insets) -> {
            Insets bars = insets.getInsets(WindowInsetsCompat.Type.systemBars());
            binding.view.getLayoutParams().height = bars.top;
            binding.view.requestLayout();
            return insets;
        });
    }

    // ---------------------------------------------------------------- Agora

    private void joinChannel() {
        try {
            ContextCompat.startForegroundService(this, new Intent(this, VideoCallForegroundService.class));
        } catch (Exception e) {
            Log.w(TAG, "Foreground service not started: " + e.getMessage());
        }

        try {
            rtcEngine = RtcEngine.create(getBaseContext(), AppConstants.appId, rtcEventHandler);
        } catch (Exception e) {
            Log.e(TAG, "RtcEngine error: " + e.getMessage());
            Toast.makeText(this, "Couldn't start the video call", Toast.LENGTH_SHORT).show();
            finish();
            return;
        }

        rtcEngine.enableVideo();
        rtcEngine.enableAudio();
        rtcEngine.setDefaultAudioRoutetoSpeakerphone(true);
        rtcEngine.muteLocalAudioStream(false);

        ChannelMediaOptions options = new ChannelMediaOptions();
        options.channelProfile = Constants.CHANNEL_PROFILE_COMMUNICATION;
        options.clientRoleType = Constants.CLIENT_ROLE_BROADCASTER;

        localTextureView = new TextureView(this);
        binding.localVideoSmallContainer.addView(localTextureView, matchParent());
        rtcEngine.setupLocalVideo(new VideoCanvas(localTextureView, VideoCanvas.RENDER_MODE_HIDDEN, 0));
        rtcEngine.startPreview();
        rtcEngine.joinChannel(agoraToken, channelName, uid, options);
    }

    private void setupRemoteVideo(int remoteUid) {
        binding.remoteVideoViewContainer.removeAllViews();
        remoteTextureView = new TextureView(this);
        binding.remoteVideoViewContainer.addView(remoteTextureView, matchParent());
        if (rtcEngine != null) {
            rtcEngine.setupRemoteVideo(new VideoCanvas(remoteTextureView, VideoCanvas.RENDER_MODE_HIDDEN, remoteUid));
        }
    }

    private void swapVideoViews() {
        if (localTextureView == null || remoteTextureView == null) return; // student not in yet
        binding.remoteVideoViewContainer.removeAllViews();
        binding.localVideoSmallContainer.removeAllViews();
        binding.remoteVideoViewContainer.addView(isSwapped ? remoteTextureView : localTextureView, matchParent());
        binding.localVideoSmallContainer.addView(isSwapped ? localTextureView : remoteTextureView, matchParent());
        isSwapped = !isSwapped;
    }

    private static ViewGroup.LayoutParams matchParent() {
        return new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT);
    }

    // Controls wired via android:onClick in activity_counsellor_video_call.xml
    public void onCallClicked(View view) {
        showExitCallDialog();
    }

    public void onSwitchCameraClicked(View view) {
        if (rtcEngine != null) rtcEngine.switchCamera();
    }

    public void onLocalAudioMuteClicked(View view) {
        muted = !muted;
        if (rtcEngine != null) rtcEngine.muteLocalAudioStream(muted);
        binding.btnMute.setImageResource(muted ? R.drawable.btn_mute : R.drawable.btn_unmute);
    }

    // ---------------------------------------------------------------- call socket

    private void connectCallSocket() {
        if (sessionId == null) return;
        socketManager = new CounsellorCallSocketManager(new CounsellorCallSocketManager.CounsellorCallSocketListener() {
            @Override public void onCallAccepted(JsonObject payload) { /* already accepted */ }

            @Override
            public void onBalanceUpdate(JsonObject payload) {
                runOnUiThread(() -> {
                    try {
                        String balance = payload.has("balance") ? payload.get("balance").getAsString() : "0";
                        if (Double.parseDouble(balance) <= 0) onForceClose("Call ended: caller's balance exhausted.");
                    } catch (NumberFormatException ignored) {
                    }
                });
            }

            @Override public void onCallCancelled(JsonObject p) { runOnUiThread(() -> onForceCloseFromPayload(p)); }
            @Override public void onCallRejected(JsonObject p) { runOnUiThread(() -> onForceCloseFromPayload(p)); }
            @Override public void onCallMissed(JsonObject p) { runOnUiThread(() -> onForceCloseFromPayload(p)); }
            @Override public void onBalanceExhausted(JsonObject p) { runOnUiThread(() -> onForceCloseFromPayload(p)); }
            @Override public void onCallEnded(JsonObject p) { runOnUiThread(() -> onForceCloseFromPayload(p)); }

            @Override
            public void onSocketFailure(Throwable t) {
                Log.e(TAG, "Call socket failed: " + t.getMessage());
            }
        });
        socketManager.connect(sessionId, Utils.getAuthToken(this)); // CollegeBook login token
    }

    private void onForceCloseFromPayload(JsonObject payload) {
        onForceClose(payload.has("body") ? payload.get("body").getAsString() : "Session ended.");
    }

    // ---------------------------------------------------------------- ending

    private void showExitCallDialog() {
        if (isSessionEnded || isForceClosing) return;
        new AlertDialog.Builder(this)
                .setTitle("End Call?")
                .setMessage("Are you sure you want to end this call?")
                .setPositiveButton("End", (d, w) -> endSession())
                .setNegativeButton("Stay", null)
                .show();
    }

    private void endSession() {
        if (isSessionEnded) return;
        isSessionEnded = true;
        if (sessionId == null || sessionId.isEmpty()) {
            leaveAndFinish();
            return;
        }
        RestClient.get().endCounsellorCall(sessionId).enqueue(new Callback<CounsellorCallEndResponse>() {
            @Override
            public void onResponse(Call<CounsellorCallEndResponse> call, Response<CounsellorCallEndResponse> response) {
                Log.d(TAG, "End call → code=" + response.code());
                leaveAndFinish(); // close either way
            }

            @Override
            public void onFailure(Call<CounsellorCallEndResponse> call, Throwable t) {
                Log.e(TAG, "End call failed: " + t.getMessage());
                leaveAndFinish();
            }
        });
    }

    private void onForceClose(String message) {
        if (isForceClosing || isFinishing()) return;
        isForceClosing = true;
        isSessionEnded = true; // back press no longer calls the end API
        new AlertDialog.Builder(this)
                .setTitle("Session Ended")
                .setMessage(message != null && !message.isEmpty() ? message : "Session ended by a participant.")
                .setCancelable(false)
                .setPositiveButton("OK", (d, w) -> leaveAndFinish())
                .show();
    }

    private void leaveAndFinish() {
        releaseCall();
        finish();
    }

    private void releaseCall() {
        stopService(new Intent(this, VideoCallForegroundService.class));
        if (socketManager != null) {
            socketManager.close();
            socketManager = null;
        }
        if (rtcEngine != null) {
            rtcEngine.leaveChannel();
            rtcEngine = null;
            new Thread(() -> {
                try {
                    RtcEngine.destroy();
                } catch (Exception e) {
                    Log.e(TAG, "RtcEngine.destroy: " + e.getMessage());
                }
            }).start();
        }
    }

    // ---------------------------------------------------------------- permissions

    private boolean checkPermissions() {
        for (String p : REQUESTED_PERMISSIONS) {
            if (ContextCompat.checkSelfPermission(this, p) != PackageManager.PERMISSION_GRANTED) return false;
        }
        return true;
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode != PERMISSION_REQ_ID) return;
        for (int r : grantResults) {
            if (r != PackageManager.PERMISSION_GRANTED) {
                Toast.makeText(this, "Camera & microphone permissions are needed for the call.", Toast.LENGTH_LONG).show();
                endSession();
                return;
            }
        }
        joinChannel();
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        releaseCall();
    }
}
