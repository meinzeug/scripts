#!/bin/bash

# =============================================================================
# UBUNTU SYSTEM MONITORING TOOLS - KOMPLETTE INSTALLATION
# Senior Developer Setup für maximale Systemübersicht
# =============================================================================

echo "🚀 Starte Installation der System-Monitoring Tools..."

# System Update
echo "📦 System Update..."
sudo apt update && sudo apt upgrade -y

# =============================================================================
# TERMINAL-BASIERTE MONITORING TOOLS
# =============================================================================

echo "🔧 Installiere Terminal-basierte Monitoring Tools..."

# Grundlegende System-Monitoring Tools
sudo apt install -y htop btop iotop nethogs iftop ncdu tree lm-sensors

# Glances - Umfassendes System-Monitoring
sudo apt install -y glances

# ctop - Docker Container Monitoring
echo "🐳 Installiere ctop für Docker Monitoring..."
sudo wget https://github.com/bcicen/ctop/releases/download/v0.7.7/ctop-0.7.7-linux-amd64 -O /usr/local/bin/ctop
sudo chmod +x /usr/local/bin/ctop

# Netdata - Real-time Performance Monitor
echo "📊 Installiere Netdata..."
bash <(curl -Ss https://my-netdata.io/kickstart.sh) --dont-wait

# =============================================================================
# GNOME EXTENSIONS FÜR DESKTOP WIDGETS
# =============================================================================

echo "🎨 Installiere GNOME Extension Manager und Abhängigkeiten..."

# GNOME Extension Manager
sudo apt install -y gnome-shell-extensions gnome-shell-extension-manager

# Abhängigkeiten für System-Monitor Extensions
sudo apt install -y gir1.2-gtop-2.0 gir1.2-networkmanager-1.0 gir1.2-clutter-1.0

# Sensor-Support für Temperatur-Monitoring
sudo apt install -y lm-sensors
sudo sensors-detect --auto

# =============================================================================
# CONKY - DESKTOP WIDGETS
# =============================================================================

echo "🖥️ Installiere Conky für Desktop Widgets..."
sudo apt install -y conky-all curl

# Erstelle Conky-Konfiguration
mkdir -p ~/.config/conky
cat > ~/.config/conky/conky.conf << 'EOF'
conky.config = {
    alignment = 'top_right',
    background = false,
    border_width = 1,
    cpu_avg_samples = 2,
    default_color = 'white',
    default_outline_color = 'white',
    default_shade_color = 'white',
    double_buffer = true,
    draw_borders = false,
    draw_graph_borders = true,
    draw_outline = false,
    draw_shades = false,
    use_xft = true,
    font = 'DejaVu Sans Mono:size=10',
    gap_x = 30,
    gap_y = 60,
    minimum_height = 5,
    minimum_width = 5,
    net_avg_samples = 2,
    no_buffers = true,
    out_to_console = false,
    out_to_stderr = false,
    extra_newline = false,
    own_window = true,
    own_window_class = 'Conky',
    own_window_type = 'desktop',
    own_window_transparent = true,
    stippled_borders = 0,
    update_interval = 1.0,
    uppercase = false,
    use_spacer = 'none',
    show_graph_scale = false,
    show_graph_range = false
}

conky.text = [[
${color grey}Info:$color ${scroll 32 Conky $conky_version - $sysname $nodename $kernel $machine}
$hr
${color grey}Uptime:$color $uptime
${color grey}Frequency (in MHz):$color $freq
${color grey}Frequency (in GHz):$color ${freq_g}
${color grey}RAM Usage:$color $mem/$memmax - $memperc% ${membar 4}
${color grey}Swap Usage:$color $swap/$swapmax - $swapperc% ${swapbar 4}
${color grey}CPU Usage:$color $cpu% ${cpubar 4}
${color grey}Processes:$color $processes  ${color grey}Running:$color $running_processes
$hr
${color grey}File systems:
 / $color${fs_used /}/${fs_size /} ${fs_bar 6 /}
${color grey}Networking:
Up:$color ${upspeed} ${color grey} - Down:$color ${downspeed}
$hr
${color grey}Name              PID   CPU%   MEM%
${color lightgrey} ${top name 1} ${top pid 1} ${top cpu 1} ${top mem 1}
${color lightgrey} ${top name 2} ${top pid 2} ${top cpu 2} ${top mem 2}
${color lightgrey} ${top name 3} ${top pid 3} ${top cpu 3} ${top mem 3}
${color lightgrey} ${top name 4} ${top pid 4} ${top cpu 4} ${top mem 4}
]]
EOF

# =============================================================================
# DOCKER MONITORING SETUP
# =============================================================================

echo "🐳 Setup Docker Monitoring..."

# Prüfe ob Docker installiert ist
if command -v docker &> /dev/null; then
    echo "Docker gefunden, konfiguriere Monitoring..."
    
    # Docker-specific monitoring tools sind bereits installiert (ctop)
    echo "ctop für Docker Container Monitoring ist installiert"
    echo "Verwendung: ctop"
else
    echo "⚠️ Docker nicht gefunden. Falls du Docker installieren möchtest:"
    echo "curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh"
fi

# =============================================================================
# PM2 MONITORING SETUP
# =============================================================================

echo "⚙️ Setup PM2 Monitoring..."

# Prüfe ob Node.js/npm installiert ist
if command -v npm &> /dev/null; then
    echo "npm gefunden, installiere PM2..."
    sudo npm install -g pm2
    echo "PM2 installiert. Verwende 'pm2 monit' für Monitoring"
else
    echo "📦 Installiere Node.js und PM2..."
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt-get install -y nodejs
    sudo npm install -g pm2
fi

# =============================================================================
# ZUSÄTZLICHE MONITORING TOOLS
# =============================================================================

echo "🔍 Installiere zusätzliche Tools..."

# Mission Center - Moderner System Monitor
if ! command -v flatpak &> /dev/null; then
    sudo apt install -y flatpak
    sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi

flatpak install -y flathub io.missioncenter.MissionCenter

# Bashtop/bpytop Alternative
sudo apt install -y python3-pip
pip3 install bpytop

# =============================================================================
# STARTUP KONFIGURATION
# =============================================================================

echo "🚀 Konfiguriere Autostart..."

# Conky Autostart
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/conky.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Conky System Monitor
Exec=conky
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

# =============================================================================
# ABSCHLUSS UND ANWEISUNGEN
# =============================================================================

echo ""
echo "🎉 Installation abgeschlossen!"
echo ""
echo "=== VERFÜGBARE TOOLS ==="
echo ""
echo "🖥️ TERMINAL-BASIERT:"
echo "  htop          - Interaktiver Process Viewer"
echo "  btop          - Moderner System Monitor"
echo "  glances       - Umfassendes Monitoring (Web-Interface: http://localhost:61208)"
echo "  iotop         - Disk I/O Monitoring"
echo "  nethogs       - Netzwerk-Usage per Prozess"
echo "  iftop         - Netzwerk-Bandwidth Monitor"
echo "  ncdu          - Disk Usage Analyzer"
echo "  sensors       - Hardware-Temperaturen"
echo ""
echo "🐳 DOCKER:"
echo "  ctop          - Docker Container Monitoring"
echo "  docker stats  - Native Docker Stats"
echo ""
echo "⚙️ PM2:"
echo "  pm2 monit     - PM2 Process Monitoring"
echo "  pm2 list      - Liste aller PM2 Prozesse"
echo "  pm2 logs      - PM2 Logs anzeigen"
echo ""
echo "🌐 WEB-BASIERT:"
echo "  Netdata       - http://localhost:19999 (nach Neustart)"
echo "  Glances Web   - glances -w (dann http://localhost:61208)"
echo ""
echo "🎨 DESKTOP WIDGETS:"
echo "  Conky         - Läuft automatisch nach Neustart"
echo "  Mission Center - Moderne GUI Alternative"
echo ""
echo "=== GNOME EXTENSIONS ==="
echo "Nach dem Neustart installiere diese Extensions über Extension Manager:"
echo "  • Astra Monitor     - Umfassendes Top-Bar Monitoring"
echo "  • Resource Monitor  - Einfaches Top-Bar Display"
echo "  • Vitals           - System Stats in Top-Bar"
echo "  • SystemStatsPlus  - Real-time Graphs"
echo ""
echo "=== NÄCHSTE SCHRITTE ==="
echo "1. Neustart: sudo reboot"
echo "2. GNOME Extension Manager öffnen"
echo "3. Extensions installieren"
echo "4. Netdata aufrufen: http://localhost:19999"
echo "5. ctop für Docker: ctop"
echo "6. PM2 Monitoring: pm2 monit"
echo ""
echo "🔥 Happy Monitoring!"
