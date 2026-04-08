#!/bin/bash

set -e

NEO4J_VERSION="4.4.48"
BLOODHOUND_VERSION="4.3.1"

NEO4J_TAR="neo4j-community-${NEO4J_VERSION}-unix.tar.gz"
NEO4J_URL="https://dist.neo4j.org/${NEO4J_TAR}"

BLOODHOUND_ZIP="BloodHound-linux-x64.zip"
BLOODHOUND_URL="https://github.com/SpecterOps/BloodHound-Legacy/releases/download/v${BLOODHOUND_VERSION}/${BLOODHOUND_ZIP}"

echo "[+] Téléchargement de Neo4j ${NEO4J_VERSION}"
wget -O ${NEO4J_TAR} "${NEO4J_URL}"

echo "[+] Extraction Neo4j"
tar -xzf ${NEO4J_TAR}
cd neo4j-community-${NEO4J_VERSION}

echo "[+] Démarrage Neo4j"
START_OUTPUT=$(./bin/neo4j start 2>&1 || true)

if echo "$START_OUTPUT" | grep -q "unsupported Java runtime"; then
    echo "[!] Java non supporté détecté. Installation OpenJDK 11..."
    sudo apt update
    sudo apt install openjdk-11-jdk -y

    echo "[+] Sélection de Java 11 (choisir manuellement si nécessaire)"
    sudo update-alternatives --config java

    echo "[+] Arrêt des processus Neo4j"
    pkill -f neo4j || true

    echo "[+] Redémarrage Neo4j"
    ./bin/neo4j start
else
    echo "[+] Neo4j démarré correctement"
fi

echo "[+] Ouverture du navigateur sur http://localhost:7474"
xdg-open http://localhost:7474 >/dev/null 2>&1 &

cd ..

echo "[+] Téléchargement BloodHound ${BLOODHOUND_VERSION}"
wget -O ${BLOODHOUND_ZIP} "${BLOODHOUND_URL}"

echo "[+] Extraction BloodHound"
unzip -o ${BLOODHOUND_ZIP}
cd BloodHound-linux-x64

echo "[+] Lancement BloodHound"
chmod +x BloodHound
./BloodHound --no-sandbox