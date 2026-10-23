package com.minibrain.collegebook.Utilities;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.core.app.NotificationManagerCompat;
import androidx.core.content.ContextCompat;

import com.google.firebase.messaging.FirebaseMessaging;

import java.util.concurrent.atomic.AtomicBoolean;

/**
 * The FCM token goes to the backend (as "registration_id" + "device_type" on OTP verify /
 * registration) only when
 * the user can actually receive notifications: permission granted (Android 13+) and
 * notifications not switched off for the app in phone settings. Otherwise nothing is sent.
 */
public final class FcmTokenHelper {

    private static final String TAG = "FcmTokenHelper";
    /** Never hold up login/registration on Firebase for longer than this. */
    private static final long TOKEN_TIMEOUT_MS = 5000;

    private static final String KEY_REGISTRATION_ID = "registration_id";
    private static final String KEY_DEVICE_TYPE = "device_type";
    private static final String DEVICE_TYPE_ANDROID = "android";

    /**
     * Adds this device to an OTP-verify / registration request — "registration_id" (the FCM
     * token) and "device_type": "android" — only when there is a token, i.e. notifications are
     * on. Declined / switched off → neither key is sent.
     */
    public static void addDeviceFields(com.google.gson.JsonObject request, String fcmToken) {
        if (fcmToken == null || fcmToken.isEmpty()) return;
        request.addProperty(KEY_REGISTRATION_ID, fcmToken);
        request.addProperty(KEY_DEVICE_TYPE, DEVICE_TYPE_ANDROID);
    }

    public interface TokenCallback {
        /** @param token the FCM token, or null when notifications are off / it couldn't be fetched */
        void onToken(String token);
    }

    private FcmTokenHelper() {
    }

    /** True when the runtime notification permission is needed and not granted yet. */
    public static boolean needsPermission(Context context) {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
                && ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED;
    }

    /** Permission granted AND the app's notifications switched on in phone settings. */
    public static boolean notificationsEnabled(Context context) {
        return !needsPermission(context) && NotificationManagerCompat.from(context).areNotificationsEnabled();
    }

    /**
     * Calls back on the main thread with the FCM token if notifications are on, else null —
     * always exactly once, at the latest after {@link #TOKEN_TIMEOUT_MS}.
     */
    public static void fetchIfNotificationsEnabled(Context context, TokenCallback callback) {
        Handler main = new Handler(Looper.getMainLooper());
        if (!notificationsEnabled(context)) {
            Log.d(TAG, "Notifications off — not sending registration_id");
            main.post(() -> callback.onToken(null));
            return;
        }

        AtomicBoolean delivered = new AtomicBoolean(false);
        Runnable timeout = () -> {
            if (delivered.compareAndSet(false, true)) {
                Log.w(TAG, "FCM token timed out — continuing without it");
                callback.onToken(null);
            }
        };
        main.postDelayed(timeout, TOKEN_TIMEOUT_MS);

        try {
            FirebaseMessaging.getInstance().getToken().addOnCompleteListener(task -> {
                if (!delivered.compareAndSet(false, true)) return;
                main.removeCallbacks(timeout);
                String token = task.isSuccessful() ? task.getResult() : null;
                if (token == null) Log.w(TAG, "FCM token unavailable", task.getException());
                callback.onToken(token);
            });
        } catch (Exception e) {
            Log.e(TAG, "FCM token error", e);
            if (delivered.compareAndSet(false, true)) {
                main.removeCallbacks(timeout);
                main.post(() -> callback.onToken(null));
            }
        }
    }
}
