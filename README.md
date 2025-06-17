# 🟩 Minecraft Server Installer

A Bash script to install and start a **Minecraft Java Edition 21 server** on **Ubuntu**.

---

## 🚀 Installation

### 1️⃣ Clone the repository

```bash
git clone https://github.com/jokikj/minecraft-1.21.5.git
cd minecraft-1.21.5
````

-----

### 2️⃣ Make scripts executable

```bash
chmod +x install_minecraft.sh start_minecraft.sh stop_minecraft.sh
```

-----

### 3️⃣ Configure environment variables

Before installation, edit the `.env` file located in the `minecraft-server` directory to set the server parameters.

```bash
vim .env
```

💡 **Example `.env` content:**

```env
# RAM allocation for the server (e.g., 2G, 4G, 8G)
RAM=8G
# Server port (default Minecraft port is 25565)
PORT=25565
```

➡ **Tip:**

  * The server will automatically run under the user account that executes the scripts.
  * Adjust the `RAM` variable (e.g., `RAM=4G`) to change the memory allocated to the server.

-----

### 4️⃣ Configure `sudoers` for non-interactive execution

To allow scripts to execute `sudo` commands without prompting for a password (essential for automation), configure `sudoers`.

On your server, open `sudo visudo`:

```bash
sudo visudo
```

Add the following line at the end of the file. **Replace `your_username` with the actual SSH username you use to run these scripts (e.g., `joki`)**:

```
your_username ALL=(ALL) NOPASSWD: /usr/bin/screen, /usr/bin/java, /usr/bin/grep, /usr/bin/cut, /usr/bin/sed, /usr/sbin/ufw, /usr/sbin/iptables, /usr/bin/wget, /usr/bin/rm, /usr/bin/chown, /usr/bin/mkdir, /usr/bin/hostname, /usr/bin/tr, /usr/bin/curl, /usr/bin/ps, /usr/bin/kill, /usr/bin/sleep, /home/your_username/minecraft-server/install_minecraft.sh, /home/your_username/minecraft-server/start_minecraft.sh, /home/your_username/minecraft-server/stop_minecraft.sh
```

  * **Important:** Replace `/home/your_username/minecraft-server/` with the actual absolute path to your cloned repository if it's different.
  * **Save and exit** `visudo`.

-----

### 5️⃣ Run the installation script

```bash
./install_minecraft.sh
```

-----

### 6️⃣ Start the server

```bash
./start_minecraft.sh
```

-----

## 🛠 Server Management

Useful commands to manage your Minecraft server:

  * **Access the server console**
    ```bash
    sudo -u $(whoami) /usr/bin/screen -r mc
    ```
  * **Detach from the console without stopping the server**
    ```
    Ctrl + A, D
    ```
  * **Stop the server cleanly (from the console)**
    ```
    /stop
    ```

-----

## 📂 Server files location

All configuration files (`server.properties`, `eula.txt`) and world data are stored in the `server` subdirectory within your cloned repository:

```
/home/$(whoami)/minecraft-server/server
```

Where `$(whoami)` is the user who executed the installation script (e.g., `/home/joki/minecraft-server/server`).

-----

## 🌐 Important Notes

✅ Ensure that your chosen port (`PORT` in the `.env`, default `25565`) is open on:

  * Your **UFW firewall** (managed by `install_minecraft.sh`)
  * Your **internet router / box** (port forwarding - *manual step*)

✅ After the server starts, both the local and public IP addresses (if accessible) will be displayed in the console.

-----

## 📎 Useful links

  * [Official Minecraft server download](https://www.minecraft.net/en-us/download/server)

<!-- end list -->

```
Vous pouvez copier ce texte et le sauvegarder dans un fichier nommé `README.md`.
```
