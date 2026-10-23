package com.minibrain.collegebook.APIServices;

import com.google.gson.JsonObject;
import com.minibrain.collegebook.Model.CounsellorCallEndResponse;
import com.minibrain.collegebook.Model.CounsellorCallResponseModel;

import okhttp3.ResponseBody;
import retrofit2.Call;
import retrofit2.http.Body;
import retrofit2.http.POST;
import retrofit2.http.Path;

/** The native API's mentor-call endpoints. */
public interface API {

    @POST("auth/fcm-token/")
    Call<ResponseBody> registerCounsellorDevice(@Body JsonObject body);

    @POST("college/call/{session_id}/accept/")
    Call<CounsellorCallResponseModel> acceptCounsellorCall(@Path("session_id") String sessionId);

    @POST("college/call/{session_id}/reject/")
    Call<CounsellorCallResponseModel> rejectCounsellorCall(@Path("session_id") String sessionId);

    @POST("college/counsellor/call/{session_id}/end/")
    Call<CounsellorCallEndResponse> endCounsellorCall(@Path("session_id") String sessionId);
}
