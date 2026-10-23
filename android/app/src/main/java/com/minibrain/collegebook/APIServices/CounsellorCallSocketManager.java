package com.minibrain.collegebook.APIServices;

import android.net.Uri;
import android.util.Log;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.WebSocket;
import okhttp3.WebSocketListener;

/**
 * Counsellor side of a live consultation call (ported from Medshow). Listens on
 * wss://<api host>/ws/call/{session}/counsellor/ for the caller hanging up, cancelling,
 * running out of balance, etc. The student side is {@link CallSocketManager} (…/user/).
 */
public class CounsellorCallSocketManager {

    private static final String TAG = "CounsellorCallSocket";

    private final OkHttpClient client = new OkHttpClient();
    private WebSocket webSocket;
    private final CounsellorCallSocketListener listener;

    public interface CounsellorCallSocketListener {
        void onCallAccepted(JsonObject payload);
        void onBalanceUpdate(JsonObject payload);
        void onCallCancelled(JsonObject payload);
        void onCallRejected(JsonObject payload);
        void onCallMissed(JsonObject payload);
        void onBalanceExhausted(JsonObject payload);
        void onCallEnded(JsonObject payload);
        void onSocketFailure(Throwable t);
    }

    public CounsellorCallSocketManager(CounsellorCallSocketListener listener) {
        this.listener = listener;
    }

    /** Same host as the REST API (dev or prod flavor). */
    private static String socketBase() {
        String host = Uri.parse(RestClient.baseUrl()).getHost();
        return "wss://" + host + "/ws/";
    }

    public void connect(String sessionId, String authToken) {
        String url = socketBase() + "call/" + sessionId + "/counsellor/?token=" + authToken;
        Request request = new Request.Builder().url(url).build();

        webSocket = client.newWebSocket(request, new WebSocketListener() {
            @Override
            public void onOpen(WebSocket webSocket, Response response) {
                Log.d(TAG, "Socket opened");
            }

            @Override
            public void onMessage(WebSocket webSocket, String text) {
                Log.d(TAG, "Socket message received");
                handleMessage(text);
            }

            @Override
            public void onFailure(WebSocket webSocket, Throwable t, Response response) {
                Log.e(TAG, "Socket failure: " + t.getMessage());
                listener.onSocketFailure(t);
            }

            @Override
            public void onClosed(WebSocket webSocket, int code, String reason) {
                Log.d(TAG, "Socket closed: " + reason);
            }
        });
    }

    private void handleMessage(String text) {
        try {
            JsonObject json = JsonParser.parseString(text).getAsJsonObject();
            String type = json.has("type") ? json.get("type").getAsString() : "";
            switch (type) {
                case "CALL_ACCEPTED": listener.onCallAccepted(json); break;
                case "BALANCE_UPDATE": listener.onBalanceUpdate(json); break;
                case "CALL_CANCELLED": listener.onCallCancelled(json); break;
                case "CALL_REJECTED": listener.onCallRejected(json); break;
                case "CALL_MISSED": listener.onCallMissed(json); break;
                case "CALL_BALANCE_EXHAUSTED": listener.onBalanceExhausted(json); break;
                case "CALL_ENDED": listener.onCallEnded(json); break;
                default: Log.d(TAG, "Unhandled type: " + type);
            }
        } catch (Exception e) {
            Log.e(TAG, "Parse error: " + e.getMessage());
        }
    }

    public void close() {
        if (webSocket != null) {
            webSocket.close(1000, "Activity destroyed");
            webSocket = null;
        }
    }
}
