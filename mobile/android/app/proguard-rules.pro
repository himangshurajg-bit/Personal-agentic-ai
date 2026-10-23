# LiteRT-LM 0.18.1's nativeSendMessageAsync uses JNI GetMethodID on this
# callback; there is no Java/Kotlin call site for R8 to discover these names.
-keep interface com.google.ai.edge.litertlm.LiteRtLmJni$JniMessageCallback {
    public void onMessage(java.lang.String);
    public void onDone();
    public void onError(int, java.lang.String);
}
-keep class com.google.ai.edge.litertlm.Conversation$JniMessageCallbackImpl {
    public void onMessage(java.lang.String);
    public void onDone();
    public void onError(int, java.lang.String);
}
