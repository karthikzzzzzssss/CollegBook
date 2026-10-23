package com.minibrain.collegebook.Model;



import com.google.gson.annotations.SerializedName;

public class CounsellorCallResponseModel {

    @SerializedName("status")
    private boolean status;
    @SerializedName("message")
    private String message;
    @SerializedName("description")
    private String description;
    @SerializedName("data")
    private Data data;

    public boolean isStatus() { return status; }
    public String getMessage() { return message; }
    public String getDescription() { return description; }
    public Data getData() { return data; }

    public static class Data {
        @SerializedName("session_id")
        private String sessionId;
        @SerializedName("channel_name")
        private String channelName;
        @SerializedName("agora_token")
        private String agoraToken;
        @SerializedName("uid")
        private int uid;

        public String getSessionId() { return sessionId; }
        public String getChannelName() { return channelName; }
        public String getAgoraToken() { return agoraToken; }
        public int getUid() { return uid; }
    }
}
