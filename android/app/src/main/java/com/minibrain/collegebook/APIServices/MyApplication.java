package com.minibrain.collegebook.APIServices;

import android.app.Application;
import android.content.Context;

/** Gives the mentor-call classes an application context, as in the native app. */
public class MyApplication extends Application {

    private static Context appContext;

    @Override
    public void onCreate() {
        super.onCreate();
        appContext = getApplicationContext();
    }

    public static Context context() {
        return appContext;
    }
}
