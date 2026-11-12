# Regras do R8 para o build de release.
#
# ML Kit (checagem de rosto do + Registrar): os componentes se registram por
# reflexão (ComponentRegistrar com construtor sem argumentos). Sem estas
# regras o R8 remove os construtores e a checagem quebra só no APK de
# release ("NoSuchMethodException: ...FaceRegistrar.<init>" e, no app,
# "Não foi possível conferir a foto agora. (código: face:error)").
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_face.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_face_bundled.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.internal.mlkit_vision_**
