#!/bin/bash
# ============================================================
# Script VPS Manager - yourvpsmaster
# Basado en el diseÃ±o exacto de las capturas
# Para Ubuntu 22.04 x86_64
# ============================================================

DIR_ROOT="/etc/yourvpsmaster"
SERVICES_DIR="$DIR_ROOT/services"
BANNER_DIR="$DIR_ROOT/banners"
HWID_DB="$DIR_ROOT/hwid.db"
TOKEN_DB="$DIR_ROOT/token.db"
USUARIOS_DB="$DIR_ROOT/usuarios.db"
BADVPN_PORT=7300

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

crear_directorios() {
    mkdir -p $DIR_ROOT $SERVICES_DIR $BANNER_DIR
    touch $HWID_DB $TOKEN_DB $USUARIOS_DB
}

set_service() {
    local service=$1
    local status=$2
    local port=$3
    echo "$status|$port" > "$SERVICES_DIR/$service"
}

get_service() {
    local service=$1
    if [[ -f "$SERVICES_DIR/$service" ]]; then
        IFS='|' read -r status port < "$SERVICES_DIR/$service"
        echo "$status|$port"
    else
        echo "off|"
    fi
}

init_services() {
    set_service "ssh" "on" "22"
    set_service "proxy_python" "off" ""
    set_service "badvpn" "off" ""
    set_service "v2ray" "off" ""
    set_service "dropbear" "off" ""
    set_service "openvpn" "off" ""
    set_service "squid" "off" ""
    set_service "trojan" "off" ""
    set_service "webmin" "off" ""
}

mostrar_info_sistema() {
    clear
    local ip=$(curl -s -4 ifconfig.me || hostname -I | awk '{print $1}')
    local fecha=$(date "+%d/%m/%Y-%H:%M")
    local cpu_cores=$(nproc)
    local ram_total=$(free -m | awk '/Mem:/ {print $2}')
    local ram_libre=$(free -m | awk '/Mem:/ {print $4}')
    local ram_uso=$((ram_total - ram_libre))
    local uso_ram=$(echo "scale=2; $ram_uso*100/$ram_total" | bc)
    local uso_cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    local buffer=$(free -m | awk '/Mem:/ {print $6}')
    
    echo -e "${GREEN}S.O: UBUNTU 22.04.5  Base:x86_64  CPU's:$cpu_cores${NC}"
    echo -e "${CYAN}IP: $ip  FECHA: $fecha${NC}"
    echo ""
    echo -e "${YELLOW}Key: Verified [yourvpsmaster] (V3.9.2) [V3.9.9]${NC}"
    echo ""
    
    local left_col=()
    declare -A service_names=(
        ["ssh"]="SSH"
        ["proxy_python"]="SOCKS/PYTHON"
        ["badvpn"]="BadVPN"
        ["v2ray"]="XRAY/UI"
        ["dropbear"]="DROPBEAR"
        ["openvpn"]="OPENVPN"
        ["squid"]="SQUID"
        ["trojan"]="TROJAN-GO"
        ["webmin"]="WEBMIN"
    )
    
    for svc in "${!service_names[@]}"; do
        IFS='|' read -r status port < <(get_service "$svc")
        if [[ "$status" == "on" && -n "$port" ]]; then
            left_col+=("${service_names[$svc]}: $port")
        fi
    done
    
    if [[ ! " ${left_col[@]} " =~ " SSH: 22 " ]]; then
        left_col=("SSH: 22" "${left_col[@]}")
    fi
    
    local num=${#left_col[@]}
    local half=$(( (num+1)/2 ))
    for ((i=0; i<half && i<7; i++)); do
        local left="${left_col[$i]}"
        local right=""
        if [[ $((i+half)) -lt $num ]]; then
            right="${left_col[$((i+half))]}"
        fi
        printf "${WHITE}%-20s    %-20s${NC}\n" "$left" "$right"
    done
    echo ""
    
    echo -e "${GREEN}TOTAL: ${ram_total}M    LIBRE: ${ram_libre}M    EN USO: ${ram_uso}M${NC}"
    echo -e "${GREEN}U/RAM: ${uso_ram}%    U/CPU: ${uso_cpu}%    BUFFER: ${buffer}M${NC}"
    echo ""
}

agregar_usuario_normal() {
    echo -e "${CYAN}CREADOR DE CUENTAS TIPO${NC}"
    read -p "Nombre de usuario: " user
    if id "$user" &>/dev/null; then
        echo -e "${RED}El usuario ya existe${NC}"
        return
    fi
    read -sp "ContraseÃ±a: " pass
    echo
    read -p "DÃ­as de expiraciÃ³n (0=sin lÃ­mite): " dias
    if [ "$dias" -gt 0 ]; then
        useradd -m -s /bin/false -e $(date -d "+$dias days" +%Y-%m-%d) $user
    else
        useradd -m -s /bin/false $user
    fi
    echo "$user:$pass" | chpasswd
    echo "$user:normal:$pass" >> $USUARIOS_DB
    echo -e "${GREEN}Usuario $user creado con Ã©xito${NC}"
    read -p "ENTER para continuar"
}

agregar_usuario_hwid() {
    echo -e "${CYAN}CREADOR DE CUENTAS TIPO${NC}"
    read -p "Nombre del usuario: " user
    if id "$user" &>/dev/null; then
        echo -e "${RED}El usuario ya existe${NC}"
        return
    fi
    read -sp "ContraseÃ±a: " pass
    echo
    read -p "HWID (dejar vacÃ­o para generar uno): " hwid
    [[ -z "$hwid" ]] && hwid=$(echo -n "$user$(date +%s)" | md5sum | awk '{print toupper($1)}')
    useradd -m -s /bin/false $user
    echo "$user:$pass" | chpasswd
    echo "$user:$hwid" >> $HWID_DB
    echo "$user:hwid:$pass" >> $USUARIOS_DB
    echo -e "${GREEN}Usuario HWID creado${NC}"
    echo -e "HWID: ${CYAN}$hwid${NC}"
    read -p "ENTER para continuar"
}

agregar_usuario_token() {
    echo -e "${CYAN}CREADOR DE CUENTAS TIPO${NC}"
    read -p "Nombre del usuario: " user
    if id "$user" &>/dev/null; then
        echo -e "${RED}El usuario ya existe${NC}"
        return
    fi
    read -sp "ContraseÃ±a: " pass
    echo
    token=$(openssl rand -hex 8)
    useradd -m -s /bin/false $user
    echo "$user:$pass" | chpasswd
    echo "$user:$token" >> $TOKEN_DB
    echo "$user:token:$pass" >> $USUARIOS_DB
    echo -e "${GREEN}Usuario TOKEN creado${NC}"
    echo -e "TOKEN: ${CYAN}$token${NC}"
    read -p "ENTER para continuar"
}

borrar_usuario() {
    read -p "Nombre de usuario a borrar: " user
    if id "$user" &>/dev/null; then
        pkill -u "$user"
        userdel -r "$user"
        sed -i "/^$user:/d" $HWID_DB $TOKEN_DB $USUARIOS_DB
        echo -e "${GREEN}Usuario $user eliminado${NC}"
    else
        echo -e "${RED}Usuario no existe${NC}"
    fi
    read -p "ENTER para continuar"
}

listar_usuarios() {
    echo -e "${YELLOW}Usuarios registrados:${NC}"
    while IFS=: read -r user tipo pass; do
        echo -e "${GREEN}$user${NC} (tipo: $tipo)"
    done < $USUARIOS_DB
    read -p "ENTER para continuar"
}

usuarios_conectados() {
    echo -e "${YELLOW}Usuarios conectados vÃ­a SSH:${NC}"
    who | grep -E "pts/[0-9]+" | awk '{print $1}' | sort -u | while read u; do
        echo -e "${GREEN}$u${NC}"
    done
    read -p "ENTER para continuar"
}

cambiar_banner_ssh() {
    read -p "Ruta del archivo banner (ej: /etc/banner): " banner_file
    if [[ -f "$banner_file" ]]; then
        if ! grep -q "^Banner" /etc/ssh/sshd_config; then
            echo "Banner $banner_file" >> /etc/ssh/sshd_config
        else
            sed -i "s|^Banner.*|Banner $banner_file|" /etc/ssh/sshd_config
        fi
        systemctl restart sshd
        echo -e "${GREEN}Banner actualizado${NC}"
    else
        echo -e "${RED}Archivo no encontrado${NC}"
    fi
    read -p "ENTER para continuar"
}

menu_proxy_python() {
    while true; do
        clear
        echo -e "${CYAN}INSTALACION DE PROTOCOLOS ( Lima )${NC}"
        echo ""
        IFS='|' read -r proxy_status proxy_port < <(get_service "proxy_python")
        if [[ "$proxy_status" == "on" ]]; then
            echo -e "${GREEN}â–º Proxy Python activo en puerto: ${proxy_port}${NC}"
            if [[ -f "$DIR_ROOT/proxy_config.conf" ]]; then
                source "$DIR_ROOT/proxy_config.conf"
                echo -e "${CYAN}  â€¢ CÃ³digo de respuesta: ${RESPONSE_CODE}${NC}"
                echo -e "${CYAN}  â€¢ Mini-Banner configurado:${NC}"
                echo -e "    ${BANNER_TEXT}${NC}"
            fi
            echo ""
        else
            echo -e "${RED}â–º Proxy Python INACTIVO${NC}"
            echo ""
        fi

        echo -e "${WHITE}[1] > Proxy (WS/Direct) (SCREEN)${NC}"
        echo -e "${WHITE}[2] > Proxy (WS/Direct) (SYSTEM) [REF]${NC}"
        echo -e "${WHITE}[3] > Proxy (WS-EPro) ( SYSTEM )${NC}"
        echo -e "${WHITE}[4] > Proxy3 (WS) ( SCREEN )${NC}"
        echo -e "${WHITE}[0] > VOLVER${NC}"
        echo ""
        read -p "â–º Opcion : " proxy_opt

        case $proxy_opt in
            1) configurar_proxy_python "screen" ;;
            2) echo -e "${YELLOW}OpciÃ³n 2 en desarrollo...${NC}"; sleep 2 ;;
            3) echo -e "${YELLOW}OpciÃ³n 3 en desarrollo...${NC}"; sleep 2 ;;
            4) echo -e "${YELLOW}OpciÃ³n 4 en desarrollo...${NC}"; sleep 2 ;;
            0) break ;;
            *) echo -e "${RED}OpciÃ³n invÃ¡lida${NC}"; sleep 2 ;;
        esac
    done
}

configurar_proxy_python() {
    clear
    echo -e "${CYAN}INSTALACION DE PROTOCOLOS ( Lima )${NC}"
    echo -e "${YELLOW}Puerto Principal, para Proxy WS/Directo${NC}"
    read -p "Puerto python: " PYTHON_PORT
    echo ""
    echo -e "${YELLOW}Puerto Local SSH/DROPBEAR/OPENVPN${NC}"
    echo -e "${WHITE}Puerto local: 22 VALIDO${NC}"
    echo ""
    echo -e "${YELLOW}RESPONDE DE CABECERA (101,200,403,500,etc)${NC}"
    echo -e "${WHITE}Response personalizado (enter por defecto 200)${NC}"
    echo -e "${WHITE}NOTA : Para OVER WEBSOCKET escribe [ 101 ]${NC}"
    read -p "RESPONSE : " RESPONSE_CODE
    RESPONSE_CODE=${RESPONSE_CODE:-200}
    echo ""
    echo -e "${YELLOW}ENCABEZADO PERSONALIZADO${NC}"
    echo -e "${WHITE}* EJEMPLO *${NC}"
    echo -e "${WHITE}\r\nContent-length: 0\r\n\r\nHTTP/1.1 200 Connection Established\r\n\r\n${NC}"
    echo -e "${WHITE}SI DESCONOCES DE ESTA OPCION${NC}"
    echo -e "${WHITE}SOLO PRESIONA ENTER${NC}"
    read -p "CABECERA : " CUSTOM_HEADER
    echo ""
    echo -e "${YELLOW}Introduzca su Mini-Banner${NC}"
    echo -e "${WHITE}Introduzca un texto [NORMAL] o en [HTML]${NC}"
    echo -e "${WHITE}-> :${NC} Script by @yourvpsmaster (Servidores privados ip Peru y cursos de creacion de servidores, Unico Yape para renovar su servidor: 994142788)"
    read -p "" BANNER_TEXT

    BANNER_ESCAPED=$(printf '%s\n' "$BANNER_TEXT" | sed 's/"/\\"/g')
    HEADER_ESCAPED=$(printf '%s\n' "$CUSTOM_HEADER" | sed 's/"/\\"/g')

    local script_path="/usr/local/bin/wsproxy_${PYTHON_PORT}.py"
    cat > "$script_path" <<EOF
#!/usr/bin/env python3
import socket
import threading
import sys

LISTEN_PORT = $PYTHON_PORT
TARGET_HOST = "127.0.0.1"
TARGET_PORT = 22
RESPONSE_CODE = "$RESPONSE_CODE"
CUSTOM_HEADER = """$HEADER_ESCAPED"""
BANNER = """$BANNER_ESCAPED"""

def handle_client(client_sock):
    try:
        request = client_sock.recv(4096)
    except:
        client_sock.close()
        return
    http_response = f"HTTP/1.1 {RESPONSE_CODE} Connection Established\\r\\n"
    if CUSTOM_HEADER:
        http_response += f"{CUSTOM_HEADER}\\r\\n"
    http_response += f"Content-Type: text/html\\r\\n"
    http_response += f"Content-Length: {len(BANNER)}\\r\\n"
    http_response += "Connection: keep-alive\\r\\n\\r\\n"
    http_response += BANNER
    client_sock.send(http_response.encode())
    remote_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    remote_sock.connect((TARGET_HOST, TARGET_PORT))
    remote_sock.send(request)
    def forward(src, dst):
        while True:
            data = src.recv(4096)
            if not data:
                break
            dst.send(data)
        src.close()
        dst.close()
    threading.Thread(target=forward, args=(client_sock, remote_sock)).start()
    forward(remote_sock, client_sock)

def start_proxy():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('0.0.0.0', LISTEN_PORT))
    server.listen(5)
    print(f"Proxy WS corriendo en puerto {LISTEN_PORT}")
    while True:
        client_sock, addr = server.accept()
        threading.Thread(target=handle_client, args=(client_sock,)).start()

if __name__ == "__main__":
    start_proxy()
EOF

    chmod +x "$script_path"

    if [ "$1" == "screen" ]; then
        screen -S "wsproxy_$PYTHON_PORT" -X quit 2>/dev/null
        screen -dmS "wsproxy_$PYTHON_PORT" python3 "$script_path"
        echo -e "${GREEN}Proxy Python iniciado en SCREEN: wsproxy_$PYTHON_PORT${NC}"
    fi

    set_service "proxy_python" "on" "$PYTHON_PORT"
    cat > "$DIR_ROOT/proxy_config.conf" <<EOF
PYTHON_PORT=$PYTHON_PORT
RESPONSE_CODE=$RESPONSE_CODE
CUSTOM_HEADER="$CUSTOM_HEADER"
BANNER_TEXT="$BANNER_TEXT"
EOF
    read -p "Presiona ENTER para continuar"
}

desactivar_proxy_python() {
    IFS='|' read -r status port < <(get_service "proxy_python")
    if [[ "$status" == "on" ]]; then
        screen -S "wsproxy_$port" -X quit 2>/dev/null
        set_service "proxy_python" "off" ""
        echo -e "${RED}Proxy Python desactivado${NC}"
    else
        echo -e "${RED}Proxy Python no estÃ¡ activo${NC}"
    fi
    read -p "ENTER para continuar"
}

instalar_badvpn() {
    IFS='|' read -r status _ < <(get_service "badvpn")
    if [[ "$status" == "on" ]]; then
        desactivar_badvpn
        return
    fi
    if ! command -v badvpn-udpgw &>/dev/null; then
        apt install -y badvpn
    fi
    screen -dmS badvpn bash -c "badvpn-udpgw --listen-addr 127.0.0.1:$BADVPN_PORT --max-clients 1000"
    iptables -t nat -C PREROUTING -p udp --dport 53 -j DNAT --to-destination 127.0.0.1:$BADVPN_PORT 2>/dev/null || \
        iptables -t nat -A PREROUTING -p udp --dport 53 -j DNAT --to-destination 127.0.0.1:$BADVPN_PORT
    set_service "badvpn" "on" "$BADVPN_PORT"
    echo -e "${GREEN}BadVPN activado en puerto $BADVPN_PORT${NC}"
    read -p "ENTER para continuar"
}

desactivar_badvpn() {
    pkill -f "badvpn-udpgw" 2>/dev/null
    iptables -t nat -D PREROUTING -p udp --dport 53 -j DNAT --to-destination 127.0.0.1:$BADVPN_PORT 2>/dev/null
    set_service "badvpn" "off" ""
    echo -e "${RED}BadVPN desactivado${NC}"
    read -p "ENTER para continuar"
}

instalar_v2ray() {
    IFS='|' read -r status _ < <(get_service "v2ray")
    if [[ "$status" == "on" ]]; then
        echo -e "${YELLOW}V2Ray ya estÃ¡ instalado.${NC}"
        read -p "ENTER para continuar"
        return
    fi
    echo -e "${CYAN}Instalando 3x-ui (V2Ray panel)...${NC}"
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
    set_service "v2ray" "on" "8080,8443,11111,62789"
    echo -e "${GREEN}3x-ui instalado. Puertos tÃ­picos: 8080,8443,11111,62789${NC}"
    read -p "ENTER para continuar"
}

menu_protocolos() {
    while true; do
        clear
        echo -e "${CYAN}INSTALACION DE PROTOCOLOS ( Lima )${NC}"
        echo ""
        IFS='|' read -r ssh_status _ < <(get_service "ssh")
        IFS='|' read -r dropbear_status _ < <(get_service "dropbear")
        IFS='|' read -r openvpn_status _ < <(get_service "openvpn")
        IFS='|' read -r squid_status _ < <(get_service "squid")
        IFS='|' read -r proxy_status _ < <(get_service "proxy_python")
        IFS='|' read -r v2ray_status _ < <(get_service "v2ray")
        IFS='|' read -r badvpn_status _ < <(get_service "badvpn")
        
        echo -e "[1] â‡¨ OpenSSH    [${GREEN}ON${NC}]    [11] â‡¨ PSIPHON SERVER [OFF]"
        echo -e "[2] â‡¨ DROPBEAR    [${dropbear_status:=OFF}]    [12] â‡¨ TCP DNS    (#BETA)"
        echo -e "[3] â‡¨ OPENVPN    [${openvpn_status:=OFF}]    [13] â‡¨ WEBMIN    [OFF]"
        echo -e "[4] â‡¨ SSL/TLS    [OFF]    [14] â‡¨ SlowDNS    [OFF]"
        echo -e "[5] â‡¨ SHADOWSOCKS-R  [OFF]    [15] â‡¨ SSL->PYTHON    [OFF]"
        echo -e "[6] â‡¨ SQUID    [${squid_status:=OFF}]    [16] â‡¨ SSLH Multiplex  [OFF]"
        echo -e "[7] â‡¨ PROXY PYTHON   [${proxy_status:=OFF}]    [17] â‡¨ OVER WEBSOCKET  (#BETA)"
        echo -e "[8] â‡¨ V2RAY SWITCH    [${v2ray_status:=OFF}]    [18] â‡¨ SOCKS5    (#BETA)"
        echo -e "[9] â‡¨ CFA ( CLASH )  [OFF]    [19] â‡¨ Protocolos UDP   [ZIP]"
        echo -e "[10] â‡¨ TROJAN-GO    [OFF]    [20] â‡¨ FUNCIONES EN DISEÃ‘O!"
        echo ""
        echo -e "${YELLOW}--- HERRAMIENTAS ---${NC}"
        echo -e "[21] â‡¨ BLOCK TORRENT    [22] â‡¨ BadVPN    [${badvpn_status:=OFF}]"
        echo -e "[23] â‡¨ TCP (BBR|Plus)    [OFF]    [24] â‡¨ FAILBAN    [OFF]"
        echo -e "[25] â‡¨ ARCHIVO ONLINE   [X0]    [26] â‡¨ UP|DOWN SpeedTest"
        echo -e "[27] â‡¨ DETALLES DEL VPS  [28] â‡¨ Block ADS    [OFF]"
        echo -e "[29] â‡¨ DNS CUSTOM (NETFLIX) [30] â‡¨ HERRAMIENTAS EXTRA"
        echo ""
        echo -e "[31] â‡¨ REINICIAR SERVICIOS [32] â‡¨ Brook Server  [OFF]"
        echo -e "[33] â‡¨ FIREWALL (IPTABLES) [34] â‡¨ Enable/Change PASS"
        echo ""
        echo -e "[35] â‡¨ AToken [APP's Mods] [0] â‡¨ REGRESAR"
        read -p "OpciÃ³n: " opt
        case $opt in
            7) 
                if [[ "$proxy_status" == "OFF" ]]; then
                    menu_proxy_python
                else
                    desactivar_proxy_python
                fi
                ;;
            8) instalar_v2ray ;;
            22) instalar_badvpn ;;
            0) break ;;
            *) echo -e "${RED}OpciÃ³n no implementada aÃºn${NC}"; sleep 2 ;;
        esac
    done
}

menu_usuarios() {
    while true; do
        clear
        echo -e "${CYAN}ADMINISTRADOR DE USUARIOS SSH|SSL|DROPBEAR${NC}"
        libre=$(free -m | awk '/Mem:/ {print $4}')
        cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
        echo -e "LIBRE: ${libre}M    USO DE CPU: ${cpu}%"
        echo ""
        echo -e "[01] âž¡ AGREGAR USUARIO(HWID/NORMAL/TOKEN)"
        echo -e "[02] âž¡ BORRAR 1/TODOS LOS USUARIO/s"
        echo -e "[03] âž¡ EDITAR/RENOVAR USUARIOS"
        echo -e "[04] âž¡ MOSTRAR USUARIOS REGISTRADOS"
        echo -e "[05] âž¡ MOSTRAR USUARIOS CONECTADOS"
        echo -e "[06] âž¡ ADD/REMOVE BANNER ( SSH/DROPBEAR )"
        echo -e "[07] âž¡ LOG DE CONSUMO ( Artificial )"
        echo -e "[08] âž¡ BLOQUEAR USUARIOS ( ALL UNLOCK )"
        echo -e "[09] âž¡ BACKUP USUARIOS (#OFFICIAL)"
        echo -e "[10] âž¡ MENU CUENTAS SSR/SS (#OFFICIAL)"
        echo -e "[11] âž¡ BOT CLIENTES TELEGRAM [ OFF ] (#BETA)"
        echo -e "[12] âž¡ VERIFICADOR CLIENTES ( INDV )"
        echo -e "[13] âž¡ ACTIVADOR CheckUser ( OFF )"
        echo -e "[14] âž¡ CONTROL DE ADMINISTRACION MULTILOGINS ( \$ )"
        echo -e "[0] âž¡ [REGRESAR]"
        echo -e "${YELLOW}(CONTADOR : [OFF]) ( ACTIVAR KILL MULTISESIONES [OFF])${NC}"
        read -p "âž¤ OpciÃ³n : " opt
        case $opt in
            1) submenu_crear_usuario ;;
            2) borrar_usuario ;;
            4) listar_usuarios ;;
            5) usuarios_conectados ;;
            6) cambiar_banner_ssh ;;
            0) break ;;
            *) echo -e "${RED}OpciÃ³n no implementada${NC}"; sleep 2 ;;
        esac
    done
}

submenu_crear_usuario() {
    clear
    echo -e "${CYAN}CREADOR DE CUENTAS TIPO${NC}"
    echo -e "[01] > SSH|DROPBEAR (DEMO)"
    echo -e "[02] > SSH|DROPBEAR"
    echo -e "[03] > HWID"
    echo -e "[04] > TOKEN"
    echo -e "[05] > MODIFICAR CONTRASEÃ‘A TOKEN"
    echo -e "[00] â‡” [ VOLVER ]"
    read -p "â–¶ OpciÃ³n : " opt
    case $opt in
        2) agregar_usuario_normal ;;
        3) agregar_usuario_hwid ;;
        4) agregar_usuario_token ;;
        0) return ;;
        *) echo -e "${RED}OpciÃ³n invÃ¡lida${NC}"; sleep 2 ;;
    esac
}

menu_principal() {
    while true; do
        mostrar_info_sistema
        echo -e "${WHITE}[01] â‡¨ CONTROL USUARIOS (SSH/SSL/VMESS)${NC}"
        echo -e "${WHITE}[02] â‡¨ [!] OPTIMIZAR VPS [OFF]${NC}"
        echo -e "${WHITE}[03] â‡¨ CONTADOR ONLINE USERS [OFF]${NC}"
        echo -e "${WHITE}[04] â‡¨ AUTOINICIAR SCRIPT [OFF]${NC}"
        echo -e "${WHITE}[05] â‡¨ INSTALADOR DE PROTOCOLOS${NC}"
        echo -e "${WHITE}[06] â‡¨ [!] UPDATE / REMOVE [0] â‡¨ [ SALIR ]${NC}"
        read -p "OpciÃ³n : " opt
        case $opt in
            1) menu_usuarios ;;
            5) menu_protocolos ;;
            6) echo -e "${GREEN}Saliendo...${NC}"; exit 0 ;;
            *) echo -e "${RED}OpciÃ³n no vÃ¡lida${NC}"; sleep 2 ;;
        esac
    done
}

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Ejecuta como root${NC}"
    exit 1
fi
crear_directorios
init_services
systemctl enable ssh
systemctl start ssh
apt update -y && apt install -y curl screen bc python3 openssl whois iptables
cp "$0" /usr/local/bin/menu 2>/dev/null || cp "install.sh" /usr/local/bin/menu
chmod +x /usr/local/bin/menu
menu_principal
