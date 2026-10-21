.class public final Lcom/android/server/wm/OtulaDensidad;
.super Ljava/lang/Object;
.source "OtulaDensidad.java"


# static fields
.field private static sReal:Ljava/lang/reflect/Field;


# direct methods
.method public constructor <init>()V
    .locals 0

    .line 19
    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method

.method public static ajusta(Ljava/lang/Object;Landroid/content/res/Configuration;Landroid/content/res/Configuration;)V
    .locals 9

    .line 24
    if-eqz p0, :cond_12

    if-eqz p1, :cond_12

    if-nez p2, :cond_0

    goto/16 :goto_8

    .line 25
    :cond_0
    :try_start_0
    const-string v0, "persist.sys.otula.dpi.apps"

    const-string v1, ""

    invoke-static {v0, v1}, Landroid/os/SystemProperties;->get(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;

    move-result-object v0

    .line 26
    if-eqz v0, :cond_11

    invoke-virtual {v0}, Ljava/lang/String;->isEmpty()Z

    move-result v1

    if-eqz v1, :cond_1

    goto/16 :goto_6

    .line 27
    :cond_1
    const-string v1, "persist.sys.otula.dpi"

    const/4 v2, 0x0

    invoke-static {v1, v2}, Landroid/os/SystemProperties;->getInt(Ljava/lang/String;I)I

    move-result v1

    .line 28
    const/16 v3, 0x78

    if-lt v1, v3, :cond_10

    const/16 v3, 0x1e0

    if-le v1, v3, :cond_2

    goto/16 :goto_5

    .line 29
    :cond_2
    iget v4, p2, Landroid/content/res/Configuration;->densityDpi:I

    .line 30
    if-lez v4, :cond_f

    if-ne v4, v1, :cond_3

    goto/16 :goto_4

    .line 32
    :cond_3
    sget-object v5, Lcom/android/server/wm/OtulaDensidad;->sReal:Ljava/lang/reflect/Field;

    const/4 v6, 0x1

    if-nez v5, :cond_4

    .line 33
    invoke-virtual {p0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;

    move-result-object v5

    const-string v7, "realActivity"

    invoke-virtual {v5, v7}, Ljava/lang/Class;->getDeclaredField(Ljava/lang/String;)Ljava/lang/reflect/Field;

    move-result-object v5

    .line 34
    invoke-virtual {v5, v6}, Ljava/lang/reflect/Field;->setAccessible(Z)V

    .line 35
    sput-object v5, Lcom/android/server/wm/OtulaDensidad;->sReal:Ljava/lang/reflect/Field;

    .line 37
    :cond_4
    sget-object v5, Lcom/android/server/wm/OtulaDensidad;->sReal:Ljava/lang/reflect/Field;

    invoke-virtual {v5, p0}, Ljava/lang/reflect/Field;->get(Ljava/lang/Object;)Ljava/lang/Object;

    move-result-object p0

    check-cast p0, Landroid/content/ComponentName;

    .line 38
    if-nez p0, :cond_5

    return-void

    .line 39
    :cond_5
    invoke-virtual {p0}, Landroid/content/ComponentName;->getPackageName()Ljava/lang/String;

    move-result-object p0

    .line 40
    nop

    .line 41
    const-string v5, ","

    invoke-virtual {v0, v5}, Ljava/lang/String;->split(Ljava/lang/String;)[Ljava/lang/String;

    move-result-object v0

    array-length v5, v0

    move v7, v2

    :goto_0
    if-ge v7, v5, :cond_7

    aget-object v8, v0, v7

    invoke-virtual {v8}, Ljava/lang/String;->trim()Ljava/lang/String;

    move-result-object v8

    invoke-virtual {v8, p0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v8

    if-eqz v8, :cond_6

    move v2, v6

    goto :goto_1

    :cond_6
    add-int/lit8 v7, v7, 0x1

    goto :goto_0

    .line 42
    :cond_7
    :goto_1
    if-nez v2, :cond_8

    return-void

    .line 44
    :cond_8
    iget p0, p2, Landroid/content/res/Configuration;->screenWidthDp:I

    iget v0, p2, Landroid/content/res/Configuration;->screenHeightDp:I

    iget v2, p2, Landroid/content/res/Configuration;->smallestScreenWidthDp:I

    .line 45
    if-lez p0, :cond_e

    if-lez v0, :cond_e

    if-gtz v2, :cond_9

    goto :goto_3

    .line 46
    :cond_9
    mul-int/2addr p0, v4

    div-int/2addr p0, v1

    .line 47
    mul-int/2addr v0, v4

    div-int/2addr v0, v1

    .line 48
    mul-int/2addr v2, v4

    div-int/2addr v2, v1

    .line 49
    iput v1, p1, Landroid/content/res/Configuration;->densityDpi:I

    .line 50
    iput p0, p1, Landroid/content/res/Configuration;->screenWidthDp:I

    .line 51
    iput v0, p1, Landroid/content/res/Configuration;->screenHeightDp:I

    .line 52
    iput v2, p1, Landroid/content/res/Configuration;->smallestScreenWidthDp:I

    .line 56
    invoke-static {p0, v0}, Ljava/lang/Math;->max(II)I

    move-result v1

    invoke-static {p0, v0}, Ljava/lang/Math;->min(II)I

    move-result p0

    .line 58
    const/16 v0, 0x3c0

    if-lt v1, v0, :cond_a

    const/16 v0, 0x2d0

    if-lt p0, v0, :cond_a

    const/4 v6, 0x4

    goto :goto_2

    .line 59
    :cond_a
    const/16 v0, 0x280

    if-lt v1, v0, :cond_b

    if-lt p0, v3, :cond_b

    const/4 v6, 0x3

    goto :goto_2

    .line 60
    :cond_b
    const/16 v0, 0x1d6

    if-lt v1, v0, :cond_c

    const/16 v0, 0x140

    if-lt p0, v0, :cond_c

    const/4 v6, 0x2

    goto :goto_2

    .line 61
    :cond_c
    nop

    .line 62
    :goto_2
    iget p0, p2, Landroid/content/res/Configuration;->screenLayout:I

    and-int/lit8 p0, p0, 0xf

    .line 63
    if-eqz p0, :cond_d

    if-ge p0, v6, :cond_d

    move v6, p0

    .line 64
    :cond_d
    iget p0, p2, Landroid/content/res/Configuration;->screenLayout:I

    and-int/lit8 p0, p0, -0x10

    or-int/2addr p0, v6

    iput p0, p1, Landroid/content/res/Configuration;->screenLayout:I
    :try_end_0
    .catchall {:try_start_0 .. :try_end_0} :catchall_0

    .line 67
    goto :goto_7

    .line 45
    :cond_e
    :goto_3
    return-void

    .line 30
    :cond_f
    :goto_4
    return-void

    .line 28
    :cond_10
    :goto_5
    return-void

    .line 26
    :cond_11
    :goto_6
    return-void

    .line 65
    :catchall_0
    move-exception p0

    .line 68
    :goto_7
    return-void

    .line 24
    :cond_12
    :goto_8
    return-void
.end method
