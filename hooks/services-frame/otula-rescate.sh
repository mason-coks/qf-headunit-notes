#!/system/bin/sh
# Red de seguridad del gancho de services.jar (proyecto K706, 2 oct 2026).
# Lo lanza init en post-fs-data, ANTES de que arranque zygote/system_server.
# Cuenta arranques; sys.boot_completed=1 pone el contador a 0 (otula_rescate.rc).
# Si van 3 arranques seguidos sin completarse, monta encima el services.jar anterior
# (bind mount: no escribe en /system) y el sistema arranca con el de antes.
# Un falso positivo (cortes de corriente al arrancar) sólo desactiva el recuadro.
F=/data/local/tmp/otula-arranques
B=/system/framework/services.jar.antes-marco-20261002
n=$(cat $F 2>/dev/null); case "$n" in ''|*[!0-9]*) n=0;; esac
n=$((n+1)); echo $n > $F
if [ $n -ge 3 ] && [ -f $B ]; then
  mount -o bind $B /system/framework/services.jar && \
    echo "$(date '+%F %T') rescate: $n arranques sin completar, montado $B" >> /data/local/tmp/otula-rescate.log
fi
