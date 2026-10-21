package com.android.server.wm;

import android.content.ComponentName;
import android.content.res.Configuration;
import android.os.SystemProperties;
import java.lang.reflect.Field;

/**
 * Proyecto K706 (7 oct 2026): densidad propia para ciertas apps.
 *
 * Google Maps se pone en modo tableta (buscador en medio panel) porque la pantalla tiene 768 dp
 * de ancho y a partir de 600 lo considera tableta. A las tareas de los paquetes de
 * persist.sys.otula.dpi.apps (separados por comas) se les da la densidad persist.sys.otula.dpi y
 * se recalcula su ancho/alto en dp: Maps se cree un móvil grande y usa su diseño de móvil. El
 * marco en píxeles no cambia (lo sigue poniendo OtulaMarco).
 *
 * Sin las properties, o ante CUALQUIER error, no toca nada: como si no existiera.
 */
public final class OtulaDensidad {
    private static Field sReal;

    public static void ajusta(Object task, Configuration out, Configuration parent) {
        try {
            if (task == null || out == null || parent == null) return;
            String apps = SystemProperties.get("persist.sys.otula.dpi.apps", "");
            if (apps == null || apps.isEmpty()) return;
            int dpi = SystemProperties.getInt("persist.sys.otula.dpi", 0);
            if (dpi < 120 || dpi > 480) return;
            int base = parent.densityDpi;
            if (base <= 0 || base == dpi) return;

            if (sReal == null) {
                Field f = task.getClass().getDeclaredField("realActivity");
                f.setAccessible(true);
                sReal = f;
            }
            ComponentName c = (ComponentName) sReal.get(task);
            if (c == null) return;
            String pkg = c.getPackageName();
            boolean es = false;
            for (String p : apps.split(",")) if (p.trim().equals(pkg)) { es = true; break; }
            if (!es) return;

            int w = parent.screenWidthDp, h = parent.screenHeightDp, sw = parent.smallestScreenWidthDp;
            if (w <= 0 || h <= 0 || sw <= 0) return;
            w = w * base / dpi;
            h = h * base / dpi;
            sw = sw * base / dpi;
            out.densityDpi = dpi;
            out.screenWidthDp = w;
            out.screenHeightDp = h;
            out.smallestScreenWidthDp = sw;

            // El tamaño de pantalla "lógico" (small/normal/large/xlarge), con las mismas reglas
            // que Configuration.reduceScreenLayout; nunca mayor que el del padre.
            int largo = Math.max(w, h), corto = Math.min(w, h);
            int talla;
            if (largo >= 960 && corto >= 720) talla = Configuration.SCREENLAYOUT_SIZE_XLARGE;
            else if (largo >= 640 && corto >= 480) talla = Configuration.SCREENLAYOUT_SIZE_LARGE;
            else if (largo >= 470 && corto >= 320) talla = Configuration.SCREENLAYOUT_SIZE_NORMAL;
            else talla = Configuration.SCREENLAYOUT_SIZE_SMALL;
            int tallaPadre = parent.screenLayout & Configuration.SCREENLAYOUT_SIZE_MASK;
            if (tallaPadre != Configuration.SCREENLAYOUT_SIZE_UNDEFINED && tallaPadre < talla) talla = tallaPadre;
            out.screenLayout = (parent.screenLayout & ~Configuration.SCREENLAYOUT_SIZE_MASK) | talla;
        } catch (Throwable t) {
            // nada: comportamiento de fábrica
        }
    }
}
