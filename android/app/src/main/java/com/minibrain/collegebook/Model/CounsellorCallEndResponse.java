package com.minibrain.collegebook.Model;

import com.google.gson.annotations.SerializedName;

public class CounsellorCallEndResponse {
    private boolean status;
    private String message;
    private String description;
    private Data data;

    public boolean isStatus() { return status; }
    public String getMessage() { return message; }
    public String getDescription() { return description; }
    public Data getData() { return data; }

    public static class Data {
        @SerializedName("session_id")
        private String sessionId;
        public String getSessionId() { return sessionId; }
    }
}