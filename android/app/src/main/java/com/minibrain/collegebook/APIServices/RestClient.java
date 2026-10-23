package com.minibrain.collegebook.APIServices;

import android.content.Context;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.minibrain.collegebook.BuildConfig;
import com.minibrain.collegebook.Utilities.Utils;

import java.util.concurrent.TimeUnit;

import okhttp3.OkHttpClient;
import okhttp3.Request;
import retrofit2.Retrofit;
import retrofit2.converter.gson.GsonConverterFactory;

/**
 * Retrofit for the mentor-call endpoints, as in the native app. The token and base URL come
 * from what Dart mirrored into {@link Utils}; token refresh stays with Dart.
 */
public class RestClient {

    private static final String DEV_BASE_URL = "https://dev.collegebook.app/api/v1/";
    private static final String PROD_BASE_URL = "https://api.collegebook.app/api/v1/";

    private static API client;
    private static String clientBaseUrl;

    /** The base URL Dart uses; before it is known, the build's default. */
    public static String baseUrl() {
        Context context = MyApplication.context();
        String saved = context != null ? Utils.getBaseUrl(context) : null;
        if (saved != null && !saved.isEmpty()) return saved;
        return BuildConfig.DEBUG ? DEV_BASE_URL : PROD_BASE_URL;
    }

    public static synchronized API get() {
        String base = baseUrl();
        if (client == null || !base.equals(clientBaseUrl)) {
            client = create(base);
            clientBaseUrl = base;
        }
        return client;
    }

    private static API create(String baseUrl) {
        Gson gson = new GsonBuilder().setDateFormat("yyyy-MM-dd'T'HH:mm:ssZ").create();
        OkHttpClient http = new OkHttpClient.Builder()
                .connectTimeout(100, TimeUnit.SECONDS)
                .readTimeout(100, TimeUnit.SECONDS)
                .writeTimeout(100, TimeUnit.SECONDS)
                .addInterceptor(chain -> {
                    // Never log the token, headers or bodies.
                    Request.Builder builder = chain.request().newBuilder()
                            .header("Accept", "application/json");
                    Context context = MyApplication.context();
                    String token = context != null ? Utils.getAuthToken(context) : null;
                    if (token != null && !token.isEmpty()) {
                        builder.header("Authorization", "Bearer " + token);
                    }
                    return chain.proceed(builder.build());
                })
                .build();
        return new Retrofit.Builder()
                .baseUrl(baseUrl)
                .client(http)
                .addConverterFactory(GsonConverterFactory.create(gson))
                .build()
                .create(API.class);
    }
}
