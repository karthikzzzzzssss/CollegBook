package com.minibrain.collegebook.APIServices;

import android.content.Context;

import com.minibrain.collegebook.Utilities.Utils;

/** Logged in = Dart has handed over a CollegeBook login token. */
public class SessionManager {

    private final Context context;

    public SessionManager(Context context) {
        this.context = context.getApplicationContext();
    }

    public boolean isLoggedIn() {
        return Utils.isLoggedIn(context);
    }
}
