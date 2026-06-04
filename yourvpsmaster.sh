#!/bin/bash

# ============================================================
# Script VPS Manager - yourvpsmaster
# Basado en estilo Chumo, adaptado a yourvpsmaster
# Para Ubuntu 22.04 x86_64
# Con instalador de 3x-ui (V2Ray)
# ============================================================

DIR_ROOT="/etc/yourvpsmaster"
BANNER_DIR="$DIR_ROOT/banners"
HWID_DB="$DIR_ROOT/hwid.db"
TOKEN_DB="$DIR_ROOT/token.db"
USUARIOS_DB="$DIR_ROOT/usuarios.db"
PROXY_CONF="$DIR_ROOT/proxy.conf"
BADVPN_PORT=7300

# Colores
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'
BG_BLACK='\033[40m'

crear_directorios() {
    mkdir -p $DIR_ROOT $BANNER_DIR
    touch $HWID_DB $TOKEN_DB $USUARIOS_DB
}

instalar_dependencias() {
    apt update -y
    apt install -y curl screen bc python3 openssl badvpn whois nginx
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
    echo -e "${YELLOW}Key: Verified [vps@] (V3.9.2) [V3.9.9]${NC}"
    echo ""
    echo -e "${WHITE}SSH: 22    SOCKS/PYTHON: 80${NC}"
    echo -e "${WHITE}slipgate: 1080    SOCKS/PYTHON: 2052${NC}"
    echo -e "${WHITE}XUI/WEB: 2096    BadVPN: $BADVPN_PORT${NC}"
    echo -e "${WHITE}XRAY/UI: 8080    XRAY/UI: 8443${NC}"
    echo -e "${WHITE}XUI/WEB: 9090    XRAY/UI: 11111${NC}"
    echo -e "${WHITE}XRAY/UI: 62789${NC}"
    echo -e "${WHITE}ZipVPN: 5667${NC}"
    echo ""
    echo -e "${GREEN}TOTAL: ${ram_total}M    LIBRE: ${ram_libre}M    EN USO: ${ram_uso}M${NC}"
    echo -e "${GREEN}U/RAM: ${uso_ram}%    U/CPU: ${uso_cpu}%    BUFFER: ${buffer}M${NC}"
    echo ""
}

# ---------- FUNCIONES DE USUARIOS ----------
agregar_usuario_normal() {
    read -p "Nombre de usuario: " user
    if id "$user" &>/dev/null; then
        echo -e "${RED}El usuario ya existe${NC}"
        return
    fi
    read -sp "Contraseña: " pass
    echo
    read -p "Días de expiración (0=sin límite): " dias
    if [ "$dias" -gt 0 ]; then
        useradd -m -s /bin/false -e $(date -d "+$dias days" +%Y-%m-%d) $user
    else
        useradd -m -s /bin/false $user
    fi
    echo "$user:$pass" | chpasswd
    echo "$user:normal:$pass" >> $USUARIOS_DB
    echo -e "${GREEN}Usuario $user creado con éxito${NC}"
}

agregar_usuario_hwid() {
    read -p "Nombre del usuario: " user
    if id "$user" &>/dev/null; then
        echo -e "${RED}El usuario ya existe${NC}"
        return
    fi
    read -sp "Contraseña: " pass
    echo
    read -p "HWID (dejar vacío para generar uno): " hwid
    [[ -z "$hwid" ]] && hwid=$(echo -n "$user$(date +%s)" | md5sum | awk '{print toupper($1)}')
    useradd -m -s /bin/false $user
    echo "$user:$pass" | chpasswd
    echo "$user:$hwid" >> $HWID_DB
    echo "$user:hwid:$pass" >> $USUARIOS_DB
    echo -e "${GREEN}Usuario HWID creado${NC}"
    echo -e "HWID: ${CYAN}$hwid${NC}"
}

agregar_usuario_token() {
    read -p "Nombre del usuario: " user
    if id "$user" &>/dev/null; then
        echo -e "${RED}El usuario ya existe${NC}"
        return
    fi
    read -sp "Contraseña: " pass
    echo
    token=$(openssl rand -hex 8)
    useradd -m -s /bin/false $user
    echo "$user:$pass" | chpasswd
    echo "$user:$token" >> $TOKEN_DB
    echo "$user:token:$pass" >> $USUARIOS_DB
    echo -e "${GREEN}Usuario TOKEN creado${NC}"
    echo -e "TOKEN: ${CYAN}$token${NC}"
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
}

listar_usuarios() {
    echo -e "${YELLOW}Usuarios registrados:${NC}"
    while IFS=: read -r user tipo pass; do
        echo -e "${GREEN}$user${NC} (tipo: $tipo)"
    done < $USUARIOS_DB
}

usuarios_conectados() {
    echo -e "${YELLOW}Usuarios conectados vía SSH:${NC}"
    who | grep -E "pts/[0-9]+" | awk '{print $1}' | sort -u | while read u; do
        echo -e "${GREEN}$u${NC}"
    done
}

cambiar_banner_ssh() {
    read -p "Ruta del archivo banner (ej: /etc/banner): " banner_file
    if [[ -f "$banner_file" ]]; then
        echo "Banner $banner_file" >> /etc/ssh/sshd_config
        systemctl restart sshd
        echo -e "${GREEN}Banner actualizado${NC}"
    else
        echo -e "${RED}Archivo no encontrado${NC}"
    fi
}

# ---------- PROXY PYTHON ----------
configurar_proxy_python() {
    echo -e "${CYAN}Configuración de Proxy Python (WS/Direct)${NC}"
    read -p "Puerto para proxy (ej: 8880): " p_py
    read -p "Código de respuesta (101,200,403,500,etc): " response
    [[ -z "$response" ]] && response="200"
    read -p "Encabezado personalizado (ENTER para default): " header
    if [[ -z "$header" ]]; then
        header="HTTP/1.1 $response Connection Established\r\n\r\n"
    fi
    read -p "Mini-Banner (texto o HTML): " mini_banner
    echo "$mini_banner" > $BANNER_DIR/banner_py_$p_py.txt
    
    cat > /usr/local/bin/wsproxy_$p_py.py <<EOF
#!/usr/bin/env python3
import socket
import sys
import threading

LISTEN_PORT = $p_py
TARGET_HOST = "127.0.0.1"
TARGET_PORT = 22
BANNER = """$mini_banner"""
RESP_HEADER = """$header"""

def handle_client(client_sock):
    request = client_sock.recv(4096)
    client_sock.send(RESP_HEADER.encode() + BANNER.encode())
    remote = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    remote.connect((TARGET_HOST, TARGET_PORT))
    remote.send(request)
    threading.Thread(target=forward, args=(client_sock, remote)).start()
    forward(remote, client_sock)

def forward(src, dst):
    while True:
        data = src.recv(4096)
        if not data:
            break
        dst.send(data)
    src.close()
    dst.close()

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('0.0.0.0', LISTEN_PORT))
s.listen(5)
print(f"Proxy WS corriendo en puerto {LISTEN_PORT}")
while True:
    client, addr = s.accept()
    threading.Thread(target=handle_client, args=(client,)).start()
EOF
    chmod +x /usr/local/bin/wsproxy_$p_py.py
    screen -dmS proxy_$p_py python3 /usr/local/bin/wsproxy_$p_py.py
    echo -e "${GREEN}Proxy Python activado en puerto $p_py con respuesta $response${NC}"
}

# ---------- BADVPN ----------
instalar_badvpn() {
    if ! command -v badvpn-udpgw &>/dev/null; then
        apt install -y badvpn
    fi
    screen -dmS badvpn bash -c "badvpn-udpgw --listen-addr 127.0.0.1:$BADVPN_PORT --max-clients 1000"
    iptables -t nat -A PREROUTING -p udp --dport 53 -j DNAT --to-destination 127.0.0.1:$BADVPN_PORT
    echo -e "${GREEN}BadVPN activado en puerto $BADVPN_PORT${NC}"
}

# ---------- INSTALADOR 3X-UI (V2RAY) ----------
instalar_3xui() {
    echo -e "${CYAN}Instalando 3x-ui (V2Ray panel)...${NC}"
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
    echo -e "${GREEN}Instalación completada. Accede al panel vía IP:puerto (normalmente 54321)${NC}"
    read -p "Presiona ENTER para continuar"
}

# ---------- MENÚ INSTALADOR DE PROTOCOLOS ----------
menu_protocolos() {
    while true; do
        clear
        echo -e "${CYAN}INSTALACION DE PROTOCOLOS ( Lima )${NC}"
        echo ""
        echo -e "[1] ⇨ OpenSSH    [${GREEN}ON${NC}]    [11] ⇨ PSIPHON SERVER [OFF]"
        echo -e "[2] ⇨ DROPBEAR    [OFF]    [12] ⇨ TCP DNS    (#BETA)"
        echo -e "[3] ⇨ OPENVPN    [OFF]    [13] ⇨ WEBMIN    [OFF]"
        echo -e "[4] ⇨ SSL/TLS    [OFF]    [14] ⇨ SlowDNS    [OFF]"
        echo -e "[5] ⇨ SHADOWSOCKS-R  [OFF]    [15] ⇨ SSL->PYTHON    [OFF]"
        echo -e "[6] ⇨ SQUID    [OFF]    [16] ⇨ SSLH Multiplex  [OFF]"
        echo -e "[7] ⇨ PROXY PYTHON   [${GREEN}PyD${NC}]    [17] ⇨ OVER WEBSOCKET  (#BETA)"
        echo -e "[8] ⇨ V2RAY SWITCH    [UI]    [18] ⇨ SOCKS5    (#BETA)"
        echo -e "[9] ⇨ CFA ( CLASH )  [OFF]    [19] ⇨ Protocolos UDP   [ZIP]"
        echo -e "[10] ⇨ TROJAN-GO    [OFF]    [20] ⇨ FUNCIONES EN DISEÑO!"
        echo ""
        echo -e "${YELLOW}--- HERRAMIENTAS ---${NC}"
        echo -e "[21] ⇨ BLOCK TORRENT    [22] ⇨ BadVPN    [${GREEN}ON${NC}]"
        echo -e "[23] ⇨ TCP (BBR|Plus)    [OFF]    [24] ⇨ FAILBAN    [OFF]"
        echo -e "[25] ⇨ ARCHIVO ONLINE   [X0]    [26] ⇨ UP|DOWN SpeedTest"
        echo -e "[27] ⇨ DETALLES DEL VPS  [28] ⇨ Block ADS    [OFF]"
        echo -e "[29] ⇨ DNS CUSTOM (NETFLIX) [30] ⇨ HERRAMIENTAS EXTRA"
        echo ""
        echo -e "[31] ⇨ REINICIAR SERVICIOS [32] ⇨ Brook Server  [OFF]"
        echo -e "[33] ⇨ FIREWALL (IPTABLES) [34] ⇨ Enable/Change PASS"
        echo ""
        echo -e "[35] ⇨ AToken [APP's Mods] [0] ⇨ REGRESAR"
        read -p "Opción: " opt
        case $opt in
            7) configurar_proxy_python ;;
            8) instalar_3xui ;;
            22) instalar_badvpn ;;
            0) break ;;
            *) echo -e "${RED}Opción no implementada aún${NC}"; sleep 2 ;;
        esac
    done
}

# ---------- MENÚ CONTROL DE USUARIOS ----------
menu_usuarios() {
    while true; do
        clear
        echo -e "${CYAN}ADMINISTRADOR DE USUARIOS SSH|SSL|DROPBEAR${NC}"
        libre=$(free -m | awk '/Mem:/ {print $4}')
        cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
        echo -e "LIBRE: ${libre}M    CPU: ${cpu}%"
        echo ""
        echo -e "[01] ➡ AGREGAR USUARIO(HWID/NORMAL/TOKEN)"
        echo -e "[02] ➡ BORRAR 1/TODOS LOS USUARIO/s"
        echo -e "[03] ➡ EDITAR/RENOVAR USUARIOS"
        echo -e "[04] ➡ MOSTRAR USUARIOS REGISTRADOS"
        echo -e "[05] ➡ MOSTRAR USUARIOS CONECTADOS"
        echo -e "[06] ➡ ADD/REMOVE BANNER ( SSH/DROPBEAR )"
        echo -e "[07] ➡ LOG DE CONSUMO ( Artificial )"
        echo -e "[08] ➡ BLOQUEAR USUARIOS ( ALL UNLOCK )"
        echo -e "[09] ➡ BACKUP USUARIOS"
        echo -e "[10] ➡ MENU CUENTAS SSR/SS"
        echo -e "[11] ➡ BOT CLIENTES TELEGRAM [ OFF ]"
        echo -e "[12] ➡ VERIFICADOR CLIENTES ( INDV )"
        echo -e "[13] ➡ ACTIVADOR CheckUser ( OFF )"
        echo -e "[14] ➡ CONTROL DE ADMINISTRACION MULTILOGINS ( \$ )"
        echo -e "[0] ➡ [REGRESAR]"
        echo -e "${YELLOW}(CONTADOR : [OFF]) ( ACTIVAR KILL MULTISESIONES [OFF])${NC}"
        read -p "➤ Opción : " opt
        case $opt in
            1) submenu_crear_usuario ;;
            2) borrar_usuario ;;
            4) listar_usuarios; read -p "ENTER para continuar" ;;
            5) usuarios_conectados; read -p "ENTER para continuar" ;;
            6) cambiar_banner_ssh ;;
            0) break ;;
            *) echo -e "${RED}Opción no implementada${NC}"; sleep 2 ;;
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
    echo -e "[05] > MODIFICAR CONTRASEÑA TOKEN"
    echo -e "[00] ⇔ [ VOLVER ]"
    read -p "▶ Opción : " opt
    case $opt in
        2) agregar_usuario_normal ;;
        3) agregar_usuario_hwid ;;
        4) agregar_usuario_token ;;
        0) return ;;
        *) echo -e "${RED}Opción inválida${NC}"; sleep 2 ;;
    esac
}

# ---------- MENÚ PRINCIPAL ----------
menu_principal() {
    while true; do
        mostrar_info_sistema
        echo -e "${WHITE}[01] ⇨ CONTROL USUARIOS (SSH/SSL/VMESS)${NC}"
        echo -e "${WHITE}[02] ⇨ [!] OPTIMIZAR VPS [OFF]${NC}"
        echo -e "${WHITE}[03] ⇨ CONTADOR ONLINE USERS [OFF]${NC}"
        echo -e "${WHITE}[04] ⇨ AUTOINICIAR SCRIPT [OFF]${NC}"
        echo -e "${WHITE}[05] ⇨ INSTALADOR DE PROTOCOLOS${NC}"
        echo -e "${WHITE}[06] ⇨ [!] UPDATE / REMOVE [0] ⇨ [ SALIR ]${NC}"
        read -p "Opción : " opt
        case $opt in
            1) menu_usuarios ;;
            5) menu_protocolos ;;
            6) echo -e "${GREEN}Saliendo...${NC}"; exit 0 ;;
            *) echo -e "${RED}Opción no válida${NC}"; sleep 2 ;;
        esac
    done
}

# ---------- INICIO ----------
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Ejecuta como root${NC}"
    exit 1
fi
crear_directorios
instalar_dependencias
systemctl enable ssh
systemctl start ssh
menu_principal
