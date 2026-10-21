.class public final Lcom/android/server/wm/OtulaMarco;
.super Ljava/lang/Object;
.source "OtulaMarco.java"

# Proyecto K706 (oct 2026): da a las ventanas de app de la pantalla principal el rectangulo de
# persist.sys.otula.appframe ("izq arriba der abajo"). Sin la property, o ante CUALQUIER error,
# devuelve el rectangulo que ya traia: mismo comportamiento que sin el gancho.

.field private static sCached:Landroid/graphics/Rect;
.field private static sLast:Ljava/lang/String;

.method public constructor <init>()V
    .locals 0
    invoke-direct {p0}, Ljava/lang/Object;-><init>()V
    return-void
.end method

.method public static marco(Lcom/android/server/wm/WindowState;Landroid/graphics/Rect;)Landroid/graphics/Rect;
    .locals 3

    :try_start_0
    if-eqz p0, :cond_fuera
    if-eqz p1, :cond_fuera

    iget-object v0, p0, Lcom/android/server/wm/WindowState;->mAttrs:Landroid/view/WindowManager$LayoutParams;
    if-eqz v0, :cond_fuera
    iget v0, v0, Landroid/view/WindowManager$LayoutParams;->type:I

    const/4 v1, 0x1
    if-eq v0, v1, :cond_tipo_ok
    const/4 v1, 0x3
    if-eq v0, v1, :cond_tipo_ok
    goto :cond_fuera

    :cond_tipo_ok
    invoke-virtual {p0}, Lcom/android/server/wm/WindowState;->isDefaultDisplay()Z
    move-result v0
    if-eqz v0, :cond_fuera

    const-string v0, "persist.sys.otula.appframe"
    const-string v1, ""
    invoke-static {v0, v1}, Landroid/os/SystemProperties;->get(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;
    move-result-object v0
    if-eqz v0, :cond_fuera
    invoke-virtual {v0}, Ljava/lang/String;->isEmpty()Z
    move-result v1
    if-nez v1, :cond_fuera

    sget-object v1, Lcom/android/server/wm/OtulaMarco;->sLast:Ljava/lang/String;
    invoke-virtual {v0, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result v1
    if-nez v1, :cond_cache
    invoke-static {v0}, Landroid/graphics/Rect;->unflattenFromString(Ljava/lang/String;)Landroid/graphics/Rect;
    move-result-object v1
    sput-object v1, Lcom/android/server/wm/OtulaMarco;->sCached:Landroid/graphics/Rect;
    sput-object v0, Lcom/android/server/wm/OtulaMarco;->sLast:Ljava/lang/String;

    :cond_cache
    sget-object v1, Lcom/android/server/wm/OtulaMarco;->sCached:Landroid/graphics/Rect;
    if-eqz v1, :cond_fuera
    invoke-virtual {v1}, Landroid/graphics/Rect;->isEmpty()Z
    move-result v2
    if-nez v2, :cond_fuera

    new-instance v2, Landroid/graphics/Rect;
    invoke-direct {v2, v1}, Landroid/graphics/Rect;-><init>(Landroid/graphics/Rect;)V
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0
    return-object v2

    :cond_fuera
    return-object p1

    :catch_0
    move-exception v0
    return-object p1
.end method
