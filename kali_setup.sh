#!/bin/bash
# -*- coding: utf-8 -*-
# =============================================================================
#  kali_setup.sh — Script unique de post-installation Kali Linux
#  Heliaq Solutions — Usage interne PASSI uniquement
#
#  USAGE : sudo bash kali_setup.sh
#
#  Ce script est AUTOSUFFISANT : il n'appelle aucun autre script externe.
#  Il couvre :
#    1. Mise à jour système complète
#    2. Création des comptes auditeurs (thomas_stephan, mathieu_clair)
#    3. Restriction des accès système
#    4. Installation de tous les outils pentest (externe + interne)
#    5. Durcissement complet (UFW, sysctl, SSH, auditd, Nessus localhost)
# =============================================================================

set -uo pipefail
export DEBIAN_FRONTEND=noninteractive

# ── Vérification root ─────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "[✗] Ce script doit être exécuté en root : sudo bash kali_setup.sh"
    exit 1
fi

# ── Chemins et constantes ─────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/heliaq_setup.log"
TOOLS_DIR="/opt/heliaq"
GITHUB_DIR="$TOOLS_DIR/github"
WORDLIST_DIR="/opt/wordlists"

# ── Comptes auditeurs ─────────────────────────────────────────────────────────
AUDITORS=("thomas_stephan" "mathieu_clair")
# Hash SHA-512 de HQS_2026!  (généré avec openssl passwd -6)
PASS_HASH='$6$R14MdYqQz9q3bMSN$UcgxZK57YjqISOtEp9x7HuIxHqV.5236ngLU5aPhNROfo76HpEgjQ66onqwR6i0iUjBzNqnv5N7Jb1idHSQB00'

mkdir -p "$TOOLS_DIR" "$GITHUB_DIR" "$WORDLIST_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "============================================================"
echo "  HELIAQ — Setup Kali Linux — $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"

# ── Helpers ───────────────────────────────────────────────────────────────────
log_ok()   { echo "[✓] $1"; }
log_info() { echo "[+] $1"; }
log_warn() { echo "[!] $1"; }
log_step() { echo ""; echo "────────────────────────────────────────────"; echo "  ÉTAPE : $1"; echo "────────────────────────────────────────────"; }

apt_install() {
    apt-get install -y --no-install-recommends "$@" >/dev/null 2>&1 \
        && log_ok "APT: $*" \
        || log_warn "APT échoué (non bloquant): $*"
}

github_clone() {
    local repo="$1"
    local dest="$GITHUB_DIR/$(basename "$repo")"
    if [[ -d "$dest/.git" ]]; then
        git -C "$dest" pull -q 2>/dev/null || true
    else
        git clone -q --depth=1 "https://github.com/$repo.git" "$dest" 2>/dev/null \
            && log_ok "Cloné: $repo" \
            || log_warn "Échec clone: $repo"
    fi
    echo "$dest"
}

# =============================================================================
# ÉTAPE 0 — CORRECTION SOURCES APT (critique après install minimale)
# =============================================================================
log_step "Correction sources APT Kali"

# Supprimer toute référence au cdrom qui bloque apt après install depuis ISO
sed -i '/^deb cdrom/d' /etc/apt/sources.list 2>/dev/null || true
sed -i '/^#.*cdrom/d' /etc/apt/sources.list 2>/dev/null || true

# S'assurer que les dépôts Kali rolling sont présents
if ! grep -q "kali-rolling" /etc/apt/sources.list 2>/dev/null; then
    cat > /etc/apt/sources.list << 'SOURCES'
deb http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware
SOURCES
    log_ok "Sources Kali rolling configurées"
else
    log_ok "Sources Kali déjà configurées"
fi

# =============================================================================
# ÉTAPE 1 — MISE À JOUR SYSTÈME
# =============================================================================
log_step "Mise à jour système"

log_info "apt update..."
apt-get update -y 2>&1 | tail -3

log_info "apt full-upgrade..."
apt-get full-upgrade -y >/dev/null 2>&1

log_info "Installation noyau linux-image-amd64..."
apt-get install -y linux-image-amd64 >/dev/null 2>&1
log_ok "Noyau linux-image-amd64 installé/à jour"

log_info "Dépendances de base (installation individuelle)..."

# Outils système essentiels
for pkg in curl wget git unzip apt-transport-https ca-certificates gnupg \
           lsb-release software-properties-common; do
    apt_install $pkg
done

# Python
for pkg in python3 python3-pip python3-venv python3-dev; do
    apt_install $pkg
done
# S'assurer que pip3 est bien disponible
if ! command -v pip3 &>/dev/null; then
    python3 -m ensurepip --upgrade 2>/dev/null || true
    ln -sf python3 /usr/bin/python 2>/dev/null || true
fi

# Build tools
for pkg in ruby ruby-dev build-essential libssl-dev libffi-dev libxml2-dev \
           libxslt1-dev zlib1g-dev; do
    apt_install $pkg
done

# Node / Java / Mono
for pkg in nodejs npm default-jre mono-complete; do
    apt_install $pkg
done

# Outils réseau et pentest natifs
for pkg in net-tools nmap masscan smbclient crackmapexec impacket-scripts \
           responder evil-winrm john hashcat hydra sqlmap nikto \
           enum4linux-ng ldap-utils proxychains4 wireshark tcpdump \
           netcat-openbsd socat; do
    apt_install $pkg
done

# ── TOUS les outils Kali par défaut (wpscan, nmap, metasploit, etc.) ─────────
log_info "Installation kali-linux-default (tous les outils standard Kali)..."
apt-get install -y kali-linux-default 2>&1 | tail -5     && log_ok "kali-linux-default installé (tous outils standard)"     || log_warn "kali-linux-default: échec, tentative outil par outil..."

# PowerShell
apt_install powershell

# Sécurité système
for pkg in ufw auditd audispd-plugins iptables-persistent \
           libpam-pwquality libpam-faillock libnotify-bin; do
    apt_install $pkg
done

# SecLists + Go
apt_install seclists
apt_install golang-go

log_ok "Mise à jour système terminée"

# =============================================================================
# ÉTAPE 2 — COMPTES AUDITEURS
# =============================================================================
log_step "Création des comptes auditeurs"

for user in "${AUDITORS[@]}"; do
    if id "$user" &>/dev/null; then
        log_warn "Compte $user existant — mise à jour mot de passe"
        usermod -p "$PASS_HASH" "$user"
    else
        useradd \
            --create-home \
            --shell /bin/bash \
            --groups sudo,wireshark,netdev \
            --password "$PASS_HASH" \
            "$user"
        log_ok "Compte créé : $user"
    fi
    # Verrouiller le compte — à déverrouiller manuellement via root
    passwd -l "$user" >/dev/null 2>&1
    log_ok "Compte $user verrouillé (déverrouiller : passwd -u $user)"
done

# Entrées sudoers dédiées
for user in "${AUDITORS[@]}"; do
    echo "$user ALL=(ALL:ALL) ALL" > "/etc/sudoers.d/$user"
    chmod 0440 "/etc/sudoers.d/$user"
done
log_ok "Droits sudo accordés aux comptes auditeurs"

# =============================================================================
# ÉTAPE 3 — RESTRICTION DES ACCÈS SYSTÈME
# =============================================================================
log_step "Restriction des accès système"

# ── 3a. Verrouiller le compte kali par défaut (si présent) ───────────────────
if id "kali" &>/dev/null; then
    passwd -l kali >/dev/null 2>&1
    usermod --expiredate 1 kali 2>/dev/null || true
    log_ok "Compte kali par défaut verrouillé et expiré"
fi

# Verrouiller le compte auditeur s'il existe (créé par le preseed)
if id "auditeur" &>/dev/null; then
    passwd -l auditeur >/dev/null 2>&1
    log_ok "Compte auditeur verrouillé (à déverrouiller via root : passwd auditeur)"
fi

# Verrouiller aussi le compte auditeur générique (créé par preseed)
if id "auditeur" &>/dev/null; then
    passwd -l auditeur >/dev/null 2>&1
    log_ok "Compte auditeur verrouillé par défaut"
fi

# ── 3b. Verrouiller root ──────────────────────────────────────────────────────
passwd -l root >/dev/null 2>&1
log_ok "Compte root verrouillé (accès via sudo uniquement)"

# ── 3c. Restreindre les connexions via PAM (access.conf) ─────────────────────
cat > /etc/security/access.conf << 'ACCESSCONF'
# Heliaq — Politique d'accès
# root toujours autorisé (première connexion pour activer les comptes)
# Comptes auditeurs autorisés une fois déverrouillés par root
+ : root           : ALL
+ : thomas_stephan : ALL
+ : mathieu_clair  : ALL
+ : auditeur       : ALL
- : ALL            : ALL
ACCESSCONF
log_ok "PAM access.conf configuré (comptes autorisés: thomas_stephan, mathieu_clair)"

# Activer pam_access dans les modules PAM concernés
for pam_file in /etc/pam.d/login /etc/pam.d/sshd /etc/pam.d/su; do
    if [[ -f "$pam_file" ]] && ! grep -q "pam_access" "$pam_file"; then
        echo "account required pam_access.so" >> "$pam_file"
    fi
done

# ── 3d. Politique de mots de passe ───────────────────────────────────────────
cat > /etc/security/pwquality.conf << 'PWCONF'
minlen = 12
minclass = 3
maxrepeat = 3
dcredit = -1
ucredit = -1
lcredit = -1
ocredit = -1
PWCONF
log_ok "Politique de mots de passe renforcée"

# ── 3e. Verrouiller les comptes système inutiles ──────────────────────────────
for sys_user in games news uucp sync lp mail; do
    passwd -l "$sys_user" 2>/dev/null || true
done
log_ok "Comptes système inutiles verrouillés"

# =============================================================================
# ÉTAPE 4 — OUTILS PENTEST EXTERNE
# =============================================================================
log_step "Installation outils pentest externe"

# ── testssl.sh ────────────────────────────────────────────────────────────────
apt_install testssl.sh

# ── subfinder ─────────────────────────────────────────────────────────────────
apt_install subfinder

# ── assetfinder ───────────────────────────────────────────────────────────────
apt_install assetfinder

# ── feroxbuster ───────────────────────────────────────────────────────────────
apt_install feroxbuster

# ── gospider ──────────────────────────────────────────────────────────────────
apt_install gospider

# ── dirsearch ─────────────────────────────────────────────────────────────────
apt_install dirsearch

# ── nuclei + templates ────────────────────────────────────────────────────────
apt_install nuclei
nuclei -update-templates -silent 2>/dev/null || true
log_ok "Nuclei + templates installés"

# ── joomscan ──────────────────────────────────────────────────────────────────
apt_install joomscan

# ── wappalyzer-cli ────────────────────────────────────────────────────────────
npm install -g @gokulapap/wappalyzer 2>/dev/null || true
log_ok "wappalyzer-cli (tentative npm)"

# ── magescan ──────────────────────────────────────────────────────────────────
MAGESCAN_DIR=$(github_clone "steverobbins/magescan")
[[ -f "$MAGESCAN_DIR/bin/magescan"    ]] && ln -sf "$MAGESCAN_DIR/bin/magescan"    /usr/local/bin/magescan 2>/dev/null || true
[[ -f "$MAGESCAN_DIR/magescan.phar"   ]] && ln -sf "$MAGESCAN_DIR/magescan.phar"   /usr/local/bin/magescan 2>/dev/null || true

# ── CMSmap ────────────────────────────────────────────────────────────────────
CMSMAP_DIR=$(github_clone "dionach/CMSmap")
pip3 install -e "$CMSMAP_DIR" --break-system-packages -q 2>/dev/null || \
    pip3 install -r "$CMSMAP_DIR/requirements.txt" --break-system-packages -q 2>/dev/null || true
[[ -f "$CMSMAP_DIR/cmsmap.py" ]] && { ln -sf "$CMSMAP_DIR/cmsmap.py" /usr/local/bin/cmsmap; chmod +x /usr/local/bin/cmsmap; }

# ── droopescan ────────────────────────────────────────────────────────────────
DROOP_DIR=$(github_clone "SamJoan/droopescan")
pip3 install -e "$DROOP_DIR" --break-system-packages -q 2>/dev/null || \
    pip3 install -r "$DROOP_DIR/requirements.txt" --break-system-packages -q 2>/dev/null || true
[[ -f "$DROOP_DIR/droopescan" ]] && { ln -sf "$DROOP_DIR/droopescan" /usr/local/bin/droopescan; chmod +x /usr/local/bin/droopescan; }

# ── katana (Go) ───────────────────────────────────────────────────────────────
export GOPATH="$HOME/go"
export PATH="$PATH:$GOPATH/bin:/usr/local/go/bin"
go install github.com/projectdiscovery/katana/cmd/katana@latest 2>/dev/null \
    && cp "$GOPATH/bin/katana" /usr/local/bin/katana 2>/dev/null \
    && log_ok "katana installé" \
    || log_warn "katana: échec go install"

# ── jwt_tool ──────────────────────────────────────────────────────────────────
JWT_DIR=$(github_clone "ticarpi/jwt_tool")
pip3 install -r "$JWT_DIR/requirements.txt" --break-system-packages -q 2>/dev/null || true
cat > /usr/local/bin/jwt_tool << WRAPPER
#!/bin/bash
python3 $JWT_DIR/jwt_tool.py "\$@"
WRAPPER
chmod +x /usr/local/bin/jwt_tool

# ── NoSQLMap ──────────────────────────────────────────────────────────────────
NOSQL_DIR=$(github_clone "codingo/NoSQLMap")
pip3 install -r "$NOSQL_DIR/requirements.txt" --break-system-packages -q 2>/dev/null || true
cat > /usr/local/bin/nosqlmap << WRAPPER
#!/bin/bash
python3 $NOSQL_DIR/nosqlmap.py "\$@"
WRAPPER
chmod +x /usr/local/bin/nosqlmap

# ── ysoserial ─────────────────────────────────────────────────────────────────
YSOS_DIR="$GITHUB_DIR/ysoserial"
mkdir -p "$YSOS_DIR"
wget -q -O "$YSOS_DIR/ysoserial.jar" \
    "https://github.com/frohoff/ysoserial/releases/download/v0.0.6/ysoserial-all.jar" 2>/dev/null || true
cat > /usr/local/bin/ysoserial << WRAPPER
#!/bin/bash
java -jar $YSOS_DIR/ysoserial.jar "\$@"
WRAPPER
chmod +x /usr/local/bin/ysoserial

# ── SSRFmap ───────────────────────────────────────────────────────────────────
SSRF_DIR=$(github_clone "swisskyrepo/SSRFmap")
pip3 install -r "$SSRF_DIR/requirements.txt" --break-system-packages -q 2>/dev/null || true
cat > /usr/local/bin/ssrfmap << WRAPPER
#!/bin/bash
python3 $SSRF_DIR/ssrfmap.py "\$@"
WRAPPER
chmod +x /usr/local/bin/ssrfmap

# ── GraphQLmap ────────────────────────────────────────────────────────────────
GQL_DIR=$(github_clone "swisskyrepo/GraphQLmap")
pip3 install -r "$GQL_DIR/requirements.txt" --break-system-packages -q 2>/dev/null || true
cat > /usr/local/bin/graphqlmap << WRAPPER
#!/bin/bash
python3 $GQL_DIR/graphqlmap.py "\$@"
WRAPPER
chmod +x /usr/local/bin/graphqlmap

log_ok "Outils pentest externe installés"

# =============================================================================
# ÉTAPE 5 — OUTILS PENTEST INTERNE / AD
# =============================================================================
log_step "Installation outils pentest interne / AD"

# ── Kerbrute ──────────────────────────────────────────────────────────────────
wget -q -O /usr/local/bin/kerbrute \
    "https://github.com/ropnop/kerbrute/releases/download/v1.0.3/kerbrute_linux_amd64" 2>/dev/null \
    && chmod +x /usr/local/bin/kerbrute \
    && log_ok "kerbrute installé" \
    || log_warn "kerbrute: échec téléchargement"

# ── bloodyAD ──────────────────────────────────────────────────────────────────
apt_install bloodyad

# ── gowitness ────────────────────────────────────────────────────────────────
log_info "Installation gowitness..."
# Essai 1 : binaire release direct (plus fiable que go install)
GOWITNESS_VER="v3.0.5"
wget -q -O /usr/local/bin/gowitness \
    "https://github.com/sensepost/gowitness/releases/download/${GOWITNESS_VER}/gowitness-linux-amd64" \
    && chmod +x /usr/local/bin/gowitness \
    && log_ok "gowitness installé (binaire $GOWITNESS_VER)" \
    || { # Essai 2 : go install
        go install github.com/sensepost/gowitness@latest 2>/dev/null \
            && cp "$GOPATH/bin/gowitness" /usr/local/bin/gowitness 2>/dev/null \
            && log_ok "gowitness installé (go install)" \
            || log_warn "gowitness: échec installation"
    }

# ── xfreerdp3 ─────────────────────────────────────────────────────────────────
log_info "Installation xfreerdp3..."
apt_install freerdp3-x11
# Alias pour compatibilité commandes existantes
if command -v xfreerdp3 &>/dev/null; then
    log_ok "xfreerdp3 installé : $(xfreerdp3 --version 2>/dev/null | head -1)"
elif command -v xfreerdp &>/dev/null; then
    ln -sf "$(command -v xfreerdp)" /usr/local/bin/xfreerdp3
    log_ok "xfreerdp3 (alias vers xfreerdp)"
fi

# ── Python libs (ldap3 + impacket) ───────────────────────────────────────────
log_info "Installation ldap3 et impacket (pip3)..."
pip3 install ldap3 impacket --break-system-packages -q \
    && log_ok "ldap3 + impacket installés via pip3" \
    || log_warn "pip3: certains modules ont échoué"

# ── PingCastle ────────────────────────────────────────────────────────────────
log_info "Installation PingCastle..."
PINGCASTLE_DIR="$TOOLS_DIR/PingCastle"
mkdir -p "$PINGCASTLE_DIR"
PINGCASTLE_VER="3.3.0.1"
wget -q -O /tmp/pingcastle.zip \
    "https://github.com/vletoux/pingcastle/releases/download/${PINGCASTLE_VER}/PingCastle_${PINGCASTLE_VER}.zip" 2>/dev/null
PINGCASTLE_OK=$?
if [[ $PINGCASTLE_OK -eq 0 ]]; then
    unzip -q -o /tmp/pingcastle.zip -d "$PINGCASTLE_DIR"
    rm -f /tmp/pingcastle.zip
    printf '#!/bin/bash\nmono %s/PingCastle.exe "$@"\n' "$PINGCASTLE_DIR" > /usr/local/bin/pingcastle
    chmod +x /usr/local/bin/pingcastle
    log_ok "PingCastle installé"
else
    log_warn "PingCastle: téléchargement échoué"
fi

# ── PowerShell modules MS365 ─────────────────────────────────────────────────
log_info "Installation modules PowerShell MS365..."
pwsh -NoProfile -NonInteractive -Command "
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
    foreach (\$mod in @('ExchangeOnlineManagement','Microsoft.Graph','AzureAD')) {
        try {
            Install-Module -Name \$mod -Scope AllUsers -Force -AllowClobber -EA Stop
            Write-Host \"[+] \$mod installé\"
        } catch { Write-Host \"[!] \$mod échoué: \$_\" }
    }
" 2>/dev/null || log_warn "Modules PS: vérifier la connexion réseau"

log_ok "Outils pentest interne installés"

# =============================================================================
# =============================================================================
# ÉTAPE 6 — NESSUS
# =============================================================================
log_step "Installation et configuration Nessus"

NESSUS_DEB="Nessus-10.11.2-ubuntu1604_amd64.deb"
NESSUS_URL="https://www.tenable.com/downloads/api/v2/pages/nessus/files/${NESSUS_DEB}"
NESSUS_KEY="W2HD-EW8E-BCTZ-JPST"
NESSUS_ADMIN_USER="thomas_stephan"
NESSUS_ADMIN_PASS="HQS_2026!"

log_info "Téléchargement Nessus..."
curl -sS --request GET --url "$NESSUS_URL" --output "/tmp/$NESSUS_DEB" \
    && dpkg -i "/tmp/$NESSUS_DEB" >/dev/null 2>&1 \
    && rm -f "/tmp/$NESSUS_DEB" \
    && log_ok "Nessus installé" \
    || log_warn "Nessus: téléchargement/installation échoué"

NESSUS_CONF="/opt/nessus/etc/nessus/nessusd.conf"
mkdir -p /opt/nessus/etc/nessus/
sed -i '/^listen_address/d' "$NESSUS_CONF" 2>/dev/null || true
echo "listen_address = 127.0.0.1" >> "$NESSUS_CONF"
log_ok "Nessus restreint à 127.0.0.1 (correction vulnérabilité écoute réseau)"

if [[ -f /opt/nessus/sbin/nessuscli ]]; then
    /opt/nessus/sbin/nessuscli fetch --register "$NESSUS_KEY" 2>/dev/null \
        && log_ok "Nessus: licence $NESSUS_KEY enregistrée" \
        || log_warn "Nessus: enregistrement licence échoué (réseau ?)"
fi

systemctl enable nessusd 2>/dev/null || true
systemctl start  nessusd 2>/dev/null || true
log_info "Attente initialisation Nessus (90s)..."
sleep 90

# Création compte admin en totale autonomie via nessuscli adduser
# stdin attendu : username, password, password confirm, admin? y
if [[ -f /opt/nessus/sbin/nessuscli ]]; then
    printf '%s\n%s\n%s\ny\n' \
        "$NESSUS_ADMIN_USER" "$NESSUS_ADMIN_PASS" "$NESSUS_ADMIN_PASS" \
        | /opt/nessus/sbin/nessuscli adduser 2>/dev/null \
        && log_ok "Nessus: compte admin '$NESSUS_ADMIN_USER' créé" \
        || {
            log_warn "nessuscli adduser échoué — tentative API REST..."
            sleep 30
            RESULT=$(curl -sk -X POST "https://127.0.0.1:8834/users" \
                -H "Content-Type: application/json" \
                -d "{\"username\":\"$NESSUS_ADMIN_USER\",\"password\":\"$NESSUS_ADMIN_PASS\",\"permissions\":128,\"type\":\"local\"}")
            echo "$RESULT" | grep -q '"id"' \
                && log_ok "Nessus: compte '$NESSUS_ADMIN_USER' créé via API" \
                || log_warn "Nessus: création compte échouée — finaliser sur https://127.0.0.1:8834 avec $NESSUS_ADMIN_USER/$NESSUS_ADMIN_PASS"
        }
fi

log_ok "Nessus opérationnel — https://127.0.0.1:8834 ($NESSUS_ADMIN_USER / $NESSUS_ADMIN_PASS)"

# =============================================================================
# ÉTAPE 7 — WORDLISTS
# =============================================================================
log_step "Téléchargement des wordlists"

dl_wordlist() {
    local url="$1" name="$2"
    wget -q -O "$WORDLIST_DIR/$name" "$url" \
        && log_ok "Wordlist: $name" \
        || log_warn "Wordlist échoué: $url"
}

dl_wordlist \
    "https://raw.githubusercontent.com/InfoSecWarrior/Offensive-Payloads/refs/heads/main/OS-Command-Injection-Windows-Payloads.txt" \
    "OS-Command-Injection-Windows-Payloads.txt"

dl_wordlist \
    "https://raw.githubusercontent.com/InfoSecWarrior/Offensive-Payloads/refs/heads/main/OS-Command-Injection-Unix-Payloads.txt" \
    "OS-Command-Injection-Unix-Payloads.txt"

dl_wordlist \
    "https://raw.githubusercontent.com/err0rr/SSTI/refs/heads/master/Wordlist" \
    "SSTI-payloads.txt"

log_ok "Wordlists disponibles dans $WORDLIST_DIR"

# =============================================================================
# ÉTAPE 8 — DURCISSEMENT SYSTÈME
# =============================================================================
log_step "Durcissement système"

# ── 8a. UFW — Pare-feu local ─────────────────────────────────────────────────
# Problème corrigé : aucun pare-feu configuré par défaut
log_info "Configuration UFW (pare-feu local)..."
apt_install ufw

ufw --force reset          >/dev/null 2>&1
ufw default deny incoming  >/dev/null 2>&1
ufw default allow outgoing >/dev/null 2>&1

# Pas d'ouverture SSH par défaut (à activer manuellement si tunnel nécessaire)
# ufw allow 2222/tcp

ufw --force enable         >/dev/null 2>&1
log_ok "UFW activé : politique deny-incoming / allow-outgoing"
log_ok "Correction vulnérabilité : pare-feu local maintenant actif"

# ── 8b. iptables complémentaires ─────────────────────────────────────────────
iptables -F INPUT 2>/dev/null || true
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p icmp --icmp-type echo-request -j DROP
iptables -A INPUT -j DROP
netfilter-persistent save >/dev/null 2>&1 || true
log_ok "Règles iptables appliquées et persistées"

# ── 8c. Sysctl ────────────────────────────────────────────────────────────────
log_info "Durcissement sysctl..."
cat > /etc/sysctl.d/99-heliaq.conf << 'SYSCTL'
# Heliaq — Durcissement noyau
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.log_martians = 1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
kernel.randomize_va_space = 2
fs.suid_dumpable = 0
kernel.core_pattern = /dev/null
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
SYSCTL
sysctl -p /etc/sysctl.d/99-heliaq.conf >/dev/null 2>&1
log_ok "Sysctl durci (ASLR, anti-spoof, no-IPv6, no-forward, no-coredump)"

# ── 8c-bis. AZERTY dans initramfs (passphrase LUKS au boot) ─────────────────
# CRITIQUE : sans ça, le clavier est QWERTY quand on tape la passphrase LUKS
log_info "Configuration clavier AZERTY dans initramfs..."

# 1. Configurer la console en AZERTY
cat > /etc/default/keyboard << 'KBCONF'
XKBMODEL="pc105"
XKBLAYOUT="fr"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
KBCONF

# 2. Configurer la console virtuelle (tty) en AZERTY
cat > /etc/default/console-setup << 'CSCONF'
ACTIVE_CONSOLES="/dev/tty[1-6]"
CHARMAP="UTF-8"
CODESET="Lat15"
FONTFACE="Fixed"
FONTSIZE="8x16"
VIDEOMODE=
CSCONF

# 3. Appliquer le clavier système
setupcon --save --force 2>/dev/null || true
dpkg-reconfigure -f noninteractive keyboard-configuration 2>/dev/null || true

# 4. Générer la keymap pour initramfs (c'est ça qui s'applique au boot LUKS)
mkdir -p /etc/initramfs-tools/
# Activer le keymap dans initramfs
if ! grep -q "^KEYMAP=y" /etc/initramfs-tools/initramfs.conf 2>/dev/null; then
    sed -i '/^KEYMAP=/d' /etc/initramfs-tools/initramfs.conf 2>/dev/null || true
    echo "KEYMAP=y" >> /etc/initramfs-tools/initramfs.conf
fi

# 5. Installer le paquet console-setup pour les keymaps
apt-get install -y console-setup keyboard-configuration >/dev/null 2>&1 || true

# 6. Régénérer l'initramfs avec le clavier AZERTY inclus
log_info "Régénération initramfs avec clavier AZERTY (peut prendre 1-2 min)..."
update-initramfs -u -k all 2>/dev/null     && log_ok "initramfs régénéré — clavier AZERTY au boot LUKS garanti"     || log_warn "update-initramfs échoué — relancer manuellement : update-initramfs -u"

# ── 8d. SSH ───────────────────────────────────────────────────────────────────
log_info "Durcissement SSH..."
SSH_CONF="/etc/ssh/sshd_config"
if [[ -f "$SSH_CONF" ]]; then
    cp "$SSH_CONF" "${SSH_CONF}.bak"
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/'  "$SSH_CONF"
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/'                "$SSH_CONF"
    sed -i 's/^#*X11Forwarding.*/X11Forwarding no/'                    "$SSH_CONF"
    sed -i 's/^#*Port .*/Port 2222/'                                    "$SSH_CONF"
    grep -q "^MaxAuthTries"    "$SSH_CONF" || echo "MaxAuthTries 3"    >> "$SSH_CONF"
    grep -q "^LoginGraceTime"  "$SSH_CONF" || echo "LoginGraceTime 30" >> "$SSH_CONF"
    grep -q "^AllowUsers"      "$SSH_CONF" || echo "AllowUsers thomas_stephan mathieu_clair" >> "$SSH_CONF"
fi
# SSH désactivé par défaut entre les missions
systemctl disable ssh 2>/dev/null || true
systemctl stop    ssh 2>/dev/null || true
log_ok "SSH durci (port 2222, no-root, no-password, désactivé par défaut)"

# ── 8e. Désactiver services inutiles ──────────────────────────────────────────
log_info "Désactivation des services inutiles..."
for svc in cups avahi-daemon bluetooth rpcbind nfs-server smbd nmbd \
           vsftpd apache2 nginx mysql postgresql redis-server; do
    if systemctl is-enabled "$svc" 2>/dev/null | grep -qE "enabled|static"; then
        systemctl stop    "$svc" 2>/dev/null || true
        systemctl disable "$svc" 2>/dev/null || true
        log_ok "Service désactivé: $svc"
    fi
done

# ── 8f. Auditd ────────────────────────────────────────────────────────────────
log_info "Configuration auditd..."
mkdir -p /etc/audit/rules.d/
cat > /etc/audit/rules.d/heliaq.rules << 'AUDITRULES'
# Heliaq Audit Rules
-a always,exit -F arch=b64 -S execve -k exec_commands
-a always,exit -F arch=b32 -S execve -k exec_commands
-w /etc/passwd   -p wa -k identity
-w /etc/shadow   -p wa -k identity
-w /etc/sudoers  -p wa -k sudo_changes
-w /var/log/     -p wa -k log_modification
-a always,exit -F arch=b64 -S open,openat -F exit=-EACCES -k access_denied
AUDITRULES
systemctl enable auditd >/dev/null 2>&1 || true
systemctl restart auditd >/dev/null 2>&1 || true
log_ok "Auditd configuré"

# ── 8g. Google Chrome ─────────────────────────────────────────────────────────
log_info "Installation Google Chrome..."
wget -q -O /tmp/chrome.deb \
    https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb 2>/dev/null \
    && dpkg -i /tmp/chrome.deb >/dev/null 2>&1 || apt-get -f install -y >/dev/null 2>&1
rm -f /tmp/chrome.deb
log_ok "Google Chrome installé"

# ── 8h. Burp Suite Pro ───────────────────────────────────────────────────────
log_info "Téléchargement Burp Suite Professional..."
BURP_URL="https://portswigger.net/burp/releases/download?product=pro&version=2026.1.5&type=Linux"
wget -q -O /tmp/burpsuite_pro.sh "$BURP_URL" 2>/dev/null \
    && chmod +x /tmp/burpsuite_pro.sh \
    && /tmp/burpsuite_pro.sh -q \
    && rm -f /tmp/burpsuite_pro.sh \
    && log_ok "Burp Suite Pro installé" \
    || log_warn "Burp Suite: téléchargement échoué"

# =============================================================================
# ÉTAPE 9 — VÉRIFICATION POST-INSTALL
# =============================================================================
log_step "Vérification post-installation"

echo ""
echo "── Comptes auditeurs ──────────────────────────────────────"
for user in "${AUDITORS[@]}"; do
    echo "  $(id $user 2>/dev/null || echo "$user : INTROUVABLE")"
done

echo ""
echo "── Ports en écoute (ne doit afficher que localhost) ───────"
ss -tlnp 2>/dev/null | grep -v "127.0.0.1\|::1\|*:*" | grep LISTEN \
    || echo "  ✓ Aucun port exposé externement"

echo ""
echo "── État UFW ───────────────────────────────────────────────"
ufw status | head -5

echo ""
echo "── Nessus ─────────────────────────────────────────────────"
grep "listen_address" /opt/nessus/etc/nessus/nessusd.conf 2>/dev/null \
    && echo "  ✓ Nessus restreint à localhost" \
    || echo "  ⚠ Fichier conf Nessus non trouvé"

echo ""
echo "── PATH Go ────────────────────────────────────────────────"
# Message de bienvenue root au premier login
cat > /root/.bashrc_heliaq_welcome << 'WELCOME'
echo ""
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║         HELIAQ — Première connexion root             ║"
echo "  ╠══════════════════════════════════════════════════════╣"
echo "  ║  Comptes disponibles (tous verrouillés) :            ║"
echo "  ║    thomas_stephan / mathieu_clair / auditeur         ║"
echo "  ║                                                      ║"
echo "  ║  Pour activer un compte :                            ║"
echo "  ║    passwd thomas_stephan                             ║"
echo "  ║    passwd mathieu_clair                              ║"
echo "  ║    passwd auditeur                                   ║"
echo "  ║                                                      ║"
echo "  ║  Pour verrouiller root ensuite :                     ║"
echo "  ║    passwd -l root                                    ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo ""
WELCOME
# Ajouter au .bashrc root (s'affiche une seule fois au premier login)
if ! grep -q "heliaq_welcome" /root/.bashrc 2>/dev/null; then
    echo 'source /root/.bashrc_heliaq_welcome 2>/dev/null' >> /root/.bashrc
fi

echo 'export GOPATH=$HOME/go'           >> /root/.bashrc
echo 'export PATH=$PATH:$GOPATH/bin'   >> /root/.bashrc
for user in "${AUDITORS[@]}"; do
    HOME_USER="/home/$user"
    if [[ -d "$HOME_USER" ]]; then
        echo 'export GOPATH=$HOME/go'         >> "$HOME_USER/.bashrc"
        echo 'export PATH=$PATH:$GOPATH/bin'  >> "$HOME_USER/.bashrc"
        chown "$user:$user" "$HOME_USER/.bashrc"
    fi
done

# =============================================================================
# ÉTAPE 10 — OUTILS INTERNES HELIAQ (repo privé)
# =============================================================================
log_step "Installation outils internes Heliaq"

HELIAQ_REPO="shan0ar/hsifugsdhfgisjgiosjgiuhdsg5456sdg"
HELIAQ_SCRIPTS_DIR="$TOOLS_DIR/heliaq-scripts"
HELIAQ_REPO_DIR=$(github_clone "$HELIAQ_REPO")
mkdir -p "$HELIAQ_SCRIPTS_DIR"

if [[ -d "$HELIAQ_REPO_DIR" ]] && [[ "$(ls -A $HELIAQ_REPO_DIR 2>/dev/null)" ]]; then
    for f in bruteforce_xmlrpc_wordpress.py gen_wordlist3.py php_enum.php samrecuperator.sh; do
        if [[ -f "$HELIAQ_REPO_DIR/$f" ]]; then
            cp "$HELIAQ_REPO_DIR/$f" "$HELIAQ_SCRIPTS_DIR/"
            chmod +x "$HELIAQ_SCRIPTS_DIR/$f"
            log_ok "Installé : $f → $HELIAQ_SCRIPTS_DIR/$f"
        else
            log_warn "$f introuvable dans le repo"
        fi
    done

    # install_auto_bloodhound.sh → exécuter directement
    if [[ -f "$HELIAQ_REPO_DIR/install_auto_bloodhound.sh" ]]; then
        cp "$HELIAQ_REPO_DIR/install_auto_bloodhound.sh" "$HELIAQ_SCRIPTS_DIR/"
        chmod +x "$HELIAQ_SCRIPTS_DIR/install_auto_bloodhound.sh"
        log_info "Lancement install_auto_bloodhound.sh en arrière-plan..."
        bash "$HELIAQ_SCRIPTS_DIR/install_auto_bloodhound.sh" &
        log_ok "BloodHound: installation lancée en arrière-plan"
    fi

    log_ok "Scripts Heliaq dans $HELIAQ_SCRIPTS_DIR"
else
    log_warn "Repo Heliaq inaccessible — scripts non installés"
    log_warn "  Réessayer : git clone https://github.com/$HELIAQ_REPO $HELIAQ_SCRIPTS_DIR"
fi

# =============================================================================
# RÉSUMÉ
# =============================================================================
echo ""
echo "============================================================"
echo "  SETUP HELIAQ TERMINÉ — $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""
echo "  COMPTES CRÉÉS :"
echo "    thomas_stephan  / mathieu_clair  (sudo, mot de passe : HQS_2026!)"
echo "    Compte kali par défaut : VERROUILLÉ"
echo "    root : VERROUILLÉ (accès via sudo)"
echo ""
echo "  PROBLÈMES CORRIGÉS :"
echo "    [✓] Nessus : écoute désormais sur 127.0.0.1:8834 uniquement"
echo "    [✓] Pare-feu UFW : actif, politique deny-incoming"
echo "    [✓] Accès système : restreint aux comptes auditeurs uniquement"
echo "    [✓] Procédure d'installation et de durcissement : documentée"
echo ""
echo "  INTERFACES :"
echo "    Nessus  : https://127.0.0.1:8834"
echo "    Burp    : lancer manuellement"
echo "    BloodHound : installer séparément si nécessaire"
echo ""
echo "  LOG    : $LOG_FILE"
echo "============================================================"
echo ""
echo "  ⚠  REDÉMARRER le système pour appliquer le nouveau noyau."
echo "     sudo reboot"
echo "============================================================"
