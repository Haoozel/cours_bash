#!/bin/bash

################
# Color variables
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
magenta='\033[0;35m'
cyan='\033[0;36m'
# Clear the color after that
clear='\033[0m'
################

################
# CHECK PREREQUISITES

# >>> Check if script is run a root <<<
if [[ $EUID -ne 0 ]]; then
    echo -e "[${red}!${clear}] Ce script doit être exécuté en tant que root. Utilisez ${yellow}sudo${clear} ou connectez-vous en tant que root."
    exit 1
fi

# >>> Check if machine can access internet <<<
function check_internet() {
    # Ping Google's public DNS server silently
    if ping -c 1 -W 1 8.8.8.8 &> /dev/null; then
        return 0  # Internet is available, no output
    else
        echo -e "[${red}!${clear}] Aucune connectivité Internet détectée."
        return 1
    fi
}

if ! check_internet; then
    echo -e "[${red}!${clear}] Ce script nécessite une connexion Internet. Veuillez vérifier votre connexion."
    exit 1
fi
################


################ FONCTIONS ################
#Fonction pour vérifier sur un utilisateur existe, puis si il est connecté. Puis proposer de tuer ses tâches.
function check_user_connection_kill() {

# Demander le login à rechercher
clear
tmp_valid=false
while [[ "$tmp_valid" == false ]]; do
echo -e "[${yellow}?${clear}] Entrez le login de l'utilisateur à rechercher : "
read login

# Vérifier si l'utilisateur existe sur le système
if ! id "$login" &>/dev/null; then
    echo -e "[${red}!${clear}] L'utilisateur $login n'existe pas sur le système."
    continue

else
tmp_valid=true
fi

done

# Vérifier si l'utilisateur est connecté
if who | grep -wq "$login"; then
    echo -e "[${green}✔${clear}] L'utilisateur $login est connecté."
    echo -e "[${blue}i${clear}] Détails des connexions :"
    who | grep -w "$login"
    
    # Proposer de tuer les processus de l'utilisateur, sauf root
    if [[ "$login" == "root" ]]; then
        echo -e "[${red}!${clear}] Impossible de tuer les processus de root pour éviter des risques système."
        read -p "Appuyez sur Entrée pour continuer..."
    else 

    while true; do
    echo -e "[${yellow}?${clear}] Voulez-vous tuer toutes les tâches de $login ? (O/N)"
        read confirm
        if [[ "$confirm" =~ ^[OoNn]$ ]]; then
            break
        else
            echo -e "[${blue}i${clear}]Vous ne pouvez répondre que par O ou N."
        fi
    done

    if [[ "$confirm" =~ ^[Oo]$ ]]; then
            pkill -u "$login"
            echo -e "[${green}✔${clear}] Tous les processus de $login ont été arrêtés."
            read -p "Appuyez sur Entrée pour continuer..."
    else
        echo -e "[${blue}i${clear}] Aucune tâche n'a été tuée."
        read -p "Appuyez sur Entrée pour continuer..."
    fi
fi

else
    echo -e "[${red}!${clear}] L'utilisateur $login n'est pas connecté."
    read -p "Appuyez sur Entrée pour continuer..."
fi
}

#Fonction pour vérifier si un utilisateur est présent dans le fichier /etc/passwd, puis afficher ses groupes
function check_user_in_passwd() {
clear
    echo -e "[${yellow}?${clear}] Entrez le login de l'utilisateur à rechercher : "
    read login

    # Vérifier si l'utilisateur est présent dans /etc/passwd
    if grep -q "^$login:" /etc/passwd; then
        echo -e "[${green}✔${clear}] L'utilisateur $login est présent dans /etc/passwd."
        user_groups=$(id -Gn "$login")
        echo -e "[${blue}i${clear}] L'utilisateur $login appartient aux groupes : ${green}$user_groups${clear}"
        read -p "Appuyez sur Entrée pour continuer..."
    else
        echo -e "[${red}!${clear}] L'utilisateur $login n'est pas présent dans /etc/passwd."
        read -p "Appuyez sur Entrée pour continuer..."
    fi
}

function backup_folder() {
## Déclaration et création de l'emplacement de sauvegarde au cas où il n'existe pas déjà
backup_path="/home/save"
mkdir -p "$backup_path" &>/dev/null
##
clear
while true; do
    echo -e "[${yellow}?${clear}] Entrez le chemin du répertoire à sauvegarder : "
    read -e directory
# Vérifier si le répertoire existe
    if [[ -d "$directory" ]]; then
        tmp_valid=false
        while [[ "$tmp_valid" == false ]]; do
            echo -e "[${yellow}?${clear}] Vous souhaitez sauvegarder le répertoire ${blue}$directory${clear} Voulez-vous continuer ? (O/N/L (L pour lister son contenu))"
            read confirm
            
            if [[ "$confirm" =~ ^[Ll]$ ]]; then
                echo -e "[${blue}i${clear}] Le dossier ${blue}$directory${clear} contient :"
                ls "$directory"
            elif [[ "$confirm" =~ ^[Oo]$ ]]; then
                tmp_valid=true
            elif [[ "$confirm" =~ ^[Nn]$ ]]; then
                echo -e "[${red}!${clear}] Suppression annulée."
                read -p "Appuyez sur Entrée pour retourner au menu."
                return
            else
                echo -e "[${blue}i${clear}] Réponse invalide. Veuillez entrer O, N ou L."
            fi
        done

            tar -czf "$backup_path/$(basename "$directory")_backup_$(date +%Y-%m-%d_%H-%M).tar.gz" "$directory" &>/dev/null
            echo -e "[${green}✔${clear}] Sauvegarde de ${blue}$directory${clear} effectuée dans ${blue}$backup_path${clear}."
            read -p "Appuyez sur Entrée pour continuer..."
            break
        else
            echo -e "[${red}!${clear}] Le répertoire $directory n'existe pas."
        fi
done
}

function lamp_install() {
clear
    lamp_info
    install_apache
    install_php
    install_mysql
    
}

# >>> FONCTIONS POUR SERVEUR LAMP <<<
function lamp_info() {
#CHECK APACHE
    if apt list --installed apache2 2>/dev/null | grep -o apache2 > /dev/null; then
        echo -e "[${green}✔${clear}] Apache est déjà installé. ${blue}||${clear} Version : $(apache2 -v | grep 'Server version')"
    else
        echo -e "[${red}!${clear}] Apache (apache2) n'est pas installé."
    fi

#CHECK PHP - avec regex pour trouver dans les modules 
    if apt list --installed 2>/dev/null | grep -Eo 'php[0-9]+\.[0-9]+' > /dev/null; then
        echo -e "[${green}✔${clear}] PHP est déjà installé. ${blue}||${clear} Version : $(php -v | head -n 1)"
    else
        echo -e "[${red}!${clear}] PHP n'est pas installé."
    fi

#CHECK MYSQL OU MARIADB
    if apt list --installed 2>/dev/null | grep -Eo "mariadb-server|mysql-server" > /dev/null; then
        echo -e "[${green}✔${clear}] MySQL (MariaDB) est déjà installé. ${blue}||${clear} Version : $(mysql --version)"
    else
        echo -e "[${red}!${clear}] MySQL (MariaDB) n'est pas installé."
    fi
    read -p "Appuyez sur Entrée pour continuer et installer les programmes manquants..."

}

function install_apache() {
clear 

    echo -e "${green}== Installation d'Apache == ${clear}"

if apt list --installed apache2 2>/dev/null | grep -o apache2 > /dev/null; then
return

else
    while true; do
        echo -e "[${yellow}?${clear}] Confirmez-vous l'installation d'Apache (apache2) ? (O/N)"
        read confirm
            if [[ "$confirm" =~ ^[Oo]$ ]]; then
                apt update && apt install -y apache2
                systemctl enable apache2 && systemctl start apache2
                if systemctl is-active --quiet apache2; then
                    echo -e "[${green}✔${clear}] Apache a été installé et démarré."
                read -p "Appuyez sur Entrée pour continuer..."
                break 
                else
                    echo -e "[${red}!${clear}] Apache a été installé mais n'a pas réussi à démarrer."
                read -p "Appuyez sur Entrée pour continuer..."
                break
                fi
            elif [[ "$confirm" =~ ^[Nn]$ ]]; then
                echo -e "[${red}!${clear}] Installation d'Apache interrompue. Arrêt du script."
                exit 1
            else 
                echo -e "[${red}!${clear}] Réponse invalide. Veuillez saisir O ou N."
            fi
    done
fi
}


function install_php() {
clear

    echo -e "${green}== Installation de PHP ==${clear}"

if apt list --installed 2>/dev/null | grep -Eo 'php[0-9]+\.[0-9]+' > /dev/null; then
    return
else

# >>> Installation du dépôt sury au préalable <<<
    echo -e "${green}== Installation de PHP == ${clear}"
    echo -e "[${blue}i${clear}] Ajout du dépôt SURY en cours... Veuillez patienter."
        apt-get update -qq
        apt-get -y install apt-transport-https lsb-release ca-certificates curl -qq
        curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg
        sh -c 'echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list'
        apt-get update -qq

# >>> Sélection de la version de php + vérification si elle existe <<<
    while true; do
        echo -e "[${yellow}?${clear}] Entrez la version de PHP que vous souhaitez installer (ex: 7.4, 8.0, 8.1, 8.2) : "
        read php_version
        php_package="php$php_version"

            if apt-cache show $php_package &>/dev/null; then
                break
            else
                echo -e "[${red}!${clear}] La version PHP spécifiée n'existe pas. Veuillez entrer une version valide."
            fi
    
    done

# >>> Installation de la version de PHP choisie <<<
    while true; do
        echo -e "[${yellow}?${clear}] Confirmez-vous l'installation de PHP $php_version. Voulez-vous l'installer ? (O/N)"
        read confirm
            if [[ "$confirm" =~ ^[Oo]$ ]]; then
                apt update && apt install -y $php_package libapache2-mod-php$php_version php$php_version-mysql
                echo -e "[${green}✔${clear}] PHP $php_version a été installé."
                read -p "Appuyez sur Entrée pour continuer..."
                break
            elif [[ "$confirm" =~ ^[Nn]$ ]]; then
            echo -e "[${red}!${clear}] Installation de PHP interrompue. Arrêt du script."
            exit 1
            else 
            echo -e "[${red}!${clear}] Réponse invalide. Veuillez saisir O ou N."
            fi
    done
fi
}

function install_mysql() {
clear

    echo -e "${green}== Installation de MySQL ==${clear}"

if apt list --installed 2>/dev/null | grep -Eo "mariadb-server|mysql-server" > /dev/null; then
    return

# >>> Installation de MySQL <<<
else
    while true; do
        echo -e "[${yellow}?${clear}] Confirmez-vous l'installation MySQL (mariadb) ? (O/N)"
        read confirm
            if [[ "$confirm" =~ ^[Oo]$ ]]; then
                apt update && apt install -y mariadb-server
                systemctl enable mysql && systemctl start mysql
                echo -e "[${green}✔${clear}] MySQL (MariaDB) a été installé et démarré."
                read -p "Appuyez sur Entrée pour continuer..."
                break
            elif [[ "$confirm" =~ ^[Nn]$ ]]; then
            echo -e "[${red}!${clear}] Installation de MySQL interrompue. Arrêt du script."
            exit 1
            else 
            echo -e "[${red}!${clear}] Réponse invalide. Veuillez saisir O ou N."
            fi
    done
fi        
}

function conf_mysql () {

check_mysql_root_password

clear

    echo -e "${green}== Configuration de MySQL ==${clear}"

# Check if MySQL/MariaDB is installed
    if ! apt list --installed 2>/dev/null | grep -Eo "mariadb-server|mysql-server" > /dev/null; then
        echo -e "[${red}!${clear}] MySQL/MariaDB n'est pas installé. Veuillez d'abord installer MySQL/MariaDB."
        read -p "Appuyez sur Entrée pour retourner au menu..."
        return
    fi

# Set or change root password

    echo -e "[${yellow}?${clear}] Voulez-vous définir ou changer le mot de passe root de MySQL/MariaDB ? (O/N)"
    while true; do
        read confirm
        if [[ "$confirm" =~ ^[Oo]$ ]]; then
        echo -e "[${blue}i${clear}] Entrez le nouveau mot de passe root pour MySQL/MariaDB :"
        read -s new_root_password
            mysql -u root -p"$root_password" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$new_root_password';"
            root_password="$new_root_password"
        echo -e "[${green}✔${clear}] Mot de passe root mis à jour."
        read -p "Appuyez sur Entrée pour continuer..."
        break
        elif [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo -e "[${blue}i${clear}] Le mot de passe root pour MySQL/MariaDB n'a pas été modifié."
        break
        else
        echo -e "[${red}!${clear}] Réponse invalide. Veuillez saisir O ou N."
        fi
    done
#Create new database and user
    
    echo -e "[${yellow}?${clear}] Voulez-vous créer une nouvelle base de données et un utilisateur ? (O/N)"
    while true; do
        read confirm
    
        if [[ "$confirm" =~ ^[Oo]$ ]]; then
            while true; do
            echo -e "[${yellow}?${clear}] Entrez le nom de la nouvelle base de données :"
            
                read db_name
                    if [[ "$db_name" == *.* ]]; then
                        echo -e "[${red}!${clear}] Le nom de la base de données ne peut pas contenir de point. Veuillez réessayer."
                    elif mysql -u root -p"$root_password" -e "USE $db_name;" 2>/dev/null; then
                        echo -e "[${red}!${clear}] La base de données '$db_name' existe déjà."
                    else
                        break
                    fi
            
            done

                mysql -u root -p"$root_password" -e "CREATE DATABASE $db_name;"
            while true; do
            echo -e "[${yellow}?${clear}] Entrez le nom du nouvel utilisateur :"
            
            read db_user
            user_exists=$(mysql -u root -p"$root_password" -sN -e "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = '$db_user' AND host = 'localhost');")
                
                if [[ "$user_exists" -eq 1 ]]; then
                    echo -e "[${red}!${clear}] L'utilisateur '$db_user' existe déjà."
                else 
                break
                fi
            done

                mysql -u root -p"$root_password" -e "CREATE USER '$db_user'@'localhost' IDENTIFIED BY '$db_password';"
                mysql -u root -p"$root_password" -e "GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'localhost';"
                mysql -u root -p"$root_password" -e "FLUSH PRIVILEGES;"
            echo -e "[${green}✔${clear}] Base de données '$db_name' et utilisateur '$db_user' créés avec succès."
            echo -e "[${green}✔${clear}] L'utilisateur '$db_user' a tous les privilèges sur la base de données '$db_name'."
            read -p "Appuyez sur Entrée pour continuer..."
            break
        elif [[ "$confirm" =~ ^[Nn]$ ]]; then
            echo -e "[${red}!${clear}] Création de base de données et utilisateur ignorés."
            read -p "Appuyez sur Entrée pour retourner au menu..."
            return
        else
        echo -e "[${red}!${clear}] Réponse invalide. Veuillez saisir O ou N."
        fi
    done
}

function check_mysql_root_password() {
    echo -e "[${blue}i${clear}] Vérification si le mot de passe root est défini pour MySQL..."

    # Attempt to connect to MySQL without a password
    if mysql -u root -e "SELECT 1;" 2>/dev/null; then
        echo -e "[${green}✔${clear}] Aucun mot de passe root n'est défini pour MySQL."
        read -p "Appuyez sur Entrée pour continuer..."
        root_password=""  # No password is set
    else
        echo -e "[${yellow}!${clear}] Un mot de passe root est défini pour MySQL."
        while true; do
            echo -e "[${blue}i${clear}] Veuillez entrer le mot de passe root pour MySQL :"
            read -s root_password

            # Validate the root password by attempting to connect
            if mysql -u root -p"$root_password" -e "SELECT 1;" 2>/dev/null; then
                echo -e "[${green}✔${clear}] Mot de passe root valide."
                read -p "Appuyez sur Entrée pour continuer..."
                break
            else
                echo -e "[${red}!${clear}] Mot de passe root incorrect. Veuillez réessayer."
            fi
        done
    fi
}


################ FIN FONCTIONS ################


# Menu interactif
while true; do
clear
echo -e "
            _               _               
           | |__   __ _ ___| |__            
  _____    | '_ \ / _' / __| '_ \   
 |_____|   | |_) | (_| \__ \ | | |  
           |_.__/ \__,_|___/_| |_|  
          ___  ___ _ __(_)_ __ | |_         
         / __|/ __| '__| | '_ \| __|  _____ 
         \__ \ (__| |  | | |_) | |_  |_____|
         |___/\___|_|  |_| .__/ \__|        
                         |_|                 
    
          ${blue}TRIPLET Alex - 02/2025${clear}

"
    echo -e "\n[${yellow}MENU${clear}] Sélectionnez une option :"
    echo ""
    echo -e "1) Vérifier la connexion d'un utilisateur"
    echo -e "2) Vérifier si l'utilisateur est présent dans ${blue}/etc/passwd${clear}, et afficher ses groupes"
    echo -e "3) Procéder à la sauvegarde d'un dossier"
    echo -e "4) Installation d'un serveur LAMP"
    echo -e "Q) Quitter"
    echo ""
    echo -ne "[${yellow}?${clear}] Choix : "
    read choice

    case "$choice" in
        1)
            check_user_connection_kill
            ;;
        2)
            check_user_in_passwd
            ;;    
        3)
            backup_folder
            ;;
        4)
            lamp_install
            ;;
        Q)
            echo -e "[${red}!${clear}] Vous avez quitté le programme."
            exit 0
            ;;
        *)
            echo -e "[${red}!${clear}] Option invalide, veuillez réessayer."
            ;;
    esac

done


