package com.minibrain.collegebook.Utilities;

import android.content.Context;
import android.content.SharedPreferences;

/**
 * The login tokens and API base URL for the native mentor-call screens. The app's own copy
 * lives in Flutter secure storage, which native code can't read, so Dart mirrors it here on
 * every save (and clears it on logout) through the collegebook/platform channel.
 */
public final class Utils {

    private static final String PREFS = "collegebook_call_auth";
    private static final String KEY_ACCESS = "access";
    private static final String KEY_REFRESH = "refresh";
    private static final String KEY_BASE_URL = "base_url";

    private Utils() {
    }

    private static SharedPreferences prefs(Context context) {
        return context.getApplicationContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    public static String getAuthToken(Context context) {
        return prefs(context).getString(KEY_ACCESS, null);
    }

    public static String getRefreshToken(Context context) {
        return prefs(context).getString(KEY_REFRESH, null);
    }

    public static boolean isLoggedIn(Context context) {
        return getAuthToken(context) != null;
    }

    /** API base URL ("https://…/api/v1/"), or null until Dart has set it. */
    public static String getBaseUrl(Context context) {
        return prefs(context).getString(KEY_BASE_URL, null);
    }

    public static void saveAuth(Context context, String access, String refresh, String baseUrl) {
        prefs(context).edit()
                .putString(KEY_ACCESS, access)
                .putString(KEY_REFRESH, refresh)
                .putString(KEY_BASE_URL, baseUrl)
                .apply();
    }

    public static void clearAuthData(Context context) {
        prefs(context).edit().remove(KEY_ACCESS).remove(KEY_REFRESH).apply();
    }
}
