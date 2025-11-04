# 📦 WordPress Catalog

[![Docker](https://img.shields.io/badge/Docker-Ready-blue?style=flat-square&logo=docker)](https://www.docker.com/)
[![WordPress](https://img.shields.io/badge/WordPress-6.4-blue?style=flat-square&logo=wordpress)](https://wordpress.org/)
[![MySQL](https://img.shields.io/badge/MySQL-8.0-orange?style=flat-square&logo=mysql)](https://www.mysql.com/)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)

A containerized WordPress catalog application with MySQL database and phpMyAdmin, ready to deploy with Docker Compose.

## ✨ Features

- 🚀 **One-command deployment** with Docker Compose
- 🔒 **Secure configuration** using environment variables
- 🏥 **Health checks** for reliable service startup
- 🌐 **Isolated networking** for enhanced security
- 💾 **Persistent data storage** with named volumes
- 🗄️ **phpMyAdmin** for easy database management
- 🔄 **Auto-restart** policies for high availability

## 🛠️ Tech Stack

- **WordPress** 6.4 - Content Management System
- **MySQL** 8.0 - Database Server
- **phpMyAdmin** - Web-based database administration
- **Docker** & **Docker Compose** - Containerization

## 📋 Prerequisites

Before you begin, ensure you have the following installed:

- [Docker](https://www.docker.com/get-started) (version 20.10 or higher)
- [Docker Compose](https://docs.docker.com/compose/install/) (version 2.0 or higher)

Verify your installation:

```bash
docker --version
docker compose version
```

## 🔗 Repository

**GitHub Repository**: [wp-catalog](https://github.com/yourusername/wp-catalog)

> 📝 **Note**: Update the repository URL above with your actual GitHub repository URL.

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/amrmarey/wp-catalog.git
cd wp-catalog
```


### 2. Configure Environment Variables

Copy the example environment file and edit it with your credentials:

```bash
cp .env.example .env
```

Edit `.env` and set your secure passwords:

```env
WP_DB_USER=wpuser
WP_DB_PASSWORD=your_strong_password_here
WP_DB_NAME=wp_catalog
MYSQL_ROOT_PASSWORD=your_strong_root_password
WP_PORT=8080
PMA_PORT=8081
```

> ⚠️ **Important**: Never commit the `.env` file to version control. It contains sensitive credentials.

### 3. Start the Services

```bash
docker compose up -d
```

This will:
- Pull the required Docker images
- Create named volumes for data persistence
- Set up the network
- Start all services in detached mode

### 4. Access Your WordPress Site

Once the containers are running, access your WordPress installation:

- **WordPress**: http://localhost:8080
- **phpMyAdmin**: http://localhost:8081

> 💡 **Note**: On first launch, WordPress will guide you through the installation wizard.

## 🧭 After Logging in to the WordPress Dashboard

Once you've completed the WordPress installation and logged into the admin dashboard, follow these steps to set up your product catalog:

### 1️⃣ Install the following plugins:

1. **WooCommerce**
   - Navigate to: Plugins → Add New
   - Search for "WooCommerce" and install the official WooCommerce plugin
   - Activate the plugin and follow the setup wizard

2. **YITH WooCommerce Catalog Mode**
   - Navigate to: Plugins → Add New
   - Search for "YITH WooCommerce Catalog Mode" and install
   - Activate the plugin

3. **Astra Theme**
   - Navigate to: Appearance → Themes → Add New
   - Search for "Astra" and install the theme
   - Activate the theme

4. **Advanced Custom Fields (ACF)**
   - Navigate to: Plugins → Add New
   - Search for "Advanced Custom Fields" and install
   - Activate the plugin

### 2️⃣ Configure the Product Catalog:

Go to: **Dashboard → WooCommerce → Settings → Catalog Mode**

Then:

- ✅ Enable "Hide Add to Cart"
- ✅ Disable all purchase and checkout options
- ✅ Optionally, add a "Request a Quote" or "Contact Us" button for inquiries

### 3️⃣ Customize the Product Page:

Go to: **ACF → Add Field Group**

Then add custom fields such as:

- **Brand** (Text)
- **Model** (Text)
- **Power** (Number)
- **Dimensions** (Text)
- **Datasheet** (File Upload)

> 💡 **Tip**: These custom fields will allow you to add detailed product specifications that are specific to your catalog needs.

## 📁 Project Structure

```
wp-catalog/
├── docker-compose.yml    # Docker Compose configuration
├── .env                  # Environment variables (not in git)
├── .env.example          # Environment template
├── .dockerignore         # Files to exclude from Docker context
├── .gitignore           # Git ignore rules
└── README.md            # This file
```

## 🔧 Configuration

### Port Configuration

Default ports are configured in `.env`:

- **WordPress**: `8080` (mapped to container port 80)
- **phpMyAdmin**: `8081` (mapped to container port 80)

To change ports, update the `WP_PORT` and `PMA_PORT` variables in your `.env` file.

### Database Configuration

Database settings can be customized in `.env`:

- `WP_DB_USER`: WordPress database user
- `WP_DB_PASSWORD`: WordPress database password
- `WP_DB_NAME`: Database name
- `MYSQL_ROOT_PASSWORD`: MySQL root password

### Volumes

The following named volumes are created for data persistence:

- `wp_data`: WordPress installation and uploaded files
- `db_data`: MySQL database files

## 🏗️ Architecture
The following diagram illustrates the network architecture and port configuration:

![Architecture Diagram](image.png)


```

```

## 🐳 Docker Services

### WordPress Service
- **Image**: `wordpress:6.4-apache`
- **Container**: `wp_catalog`
- **Port**: `8080:80`
- **Volume**: `wp_data:/var/www/html`
- **Health Check**: Checks WordPress installation status

### MySQL Service
- **Image**: `mysql:8.0`
- **Container**: `wp_catalog_db`
- **Port**: Internal only (3306)
- **Volume**: `db_data:/var/lib/mysql`
- **Health Check**: MySQL ping test

### phpMyAdmin Service
- **Image**: `phpmyadmin/phpmyadmin:latest`
- **Container**: `wp_catalog_pma`
- **Port**: `8081:80`
- **Health Check**: Depends on MySQL being healthy

## 📝 Common Commands

### View Running Containers

```bash
docker compose ps
```

### View Logs

```bash
# All services
docker compose logs

# Specific service
docker compose logs wordpress
docker compose logs db

# Follow logs
docker compose logs -f wordpress
```

### Stop Services

```bash
docker compose stop
```

### Start Services

```bash
docker compose start
```

### Restart Services

```bash
docker compose restart
```

### Stop and Remove Containers

```bash
docker compose down
```

### Stop and Remove Containers + Volumes

```bash
# ⚠️ WARNING: This will delete all data
docker compose down -v
```

### Rebuild Services

```bash
docker compose up -d --build
```

## 🔍 Troubleshooting

### WordPress Not Loading

1. Check if containers are running:
   ```bash
   docker compose ps
   ```

2. Check WordPress logs:
   ```bash
   docker compose logs wordpress
   ```

3. Verify database connection:
   ```bash
   docker compose logs db
   ```

### Database Connection Issues

1. Ensure the database container is healthy:
   ```bash
   docker compose ps db
   ```

2. Verify environment variables are set correctly in `.env`

3. Check MySQL logs:
   ```bash
   docker compose logs db
   ```

### Port Already in Use

If you get an error about ports being in use:

1. Change the ports in `.env`:
   ```env
   WP_PORT=8082
   PMA_PORT=8083
   ```

2. Or stop the service using the port:
   ```bash
   # Find process using port 8080 (Windows)
   netstat -ano | findstr :8080
   ```

### Reset Everything

To start fresh (⚠️ deletes all data):

```bash
docker compose down -v
docker volume prune
# Then start again
docker compose up -d
```

## 🔒 Security Best Practices

- ✅ Use strong, unique passwords in `.env`
- ✅ Never commit `.env` to version control
- ✅ Keep Docker images updated
- ✅ Use specific image versions (not `latest`)
- ✅ Regularly backup your volumes
- ✅ Review WordPress security plugins

## 💾 Backup & Restore

### Backup Database

```bash
docker compose exec db mysqldump -u wpuser -p wp_catalog > backup.sql
```

### Backup WordPress Files

```bash
docker compose cp wp_catalog:/var/www/html ./wp_backup
```

### Restore Database

```bash
docker compose exec -T db mysql -u wpuser -p wp_catalog < backup.sql
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

For questions or suggestions, contact the maintainer:

- **Email**: [amr.marey@msn.com](mailto:amr.marey@msn.com)

### How to Contribute

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

We appreciate your contributions! 🎉

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [WordPress](https://wordpress.org/) - Open source CMS
- [MySQL](https://www.mysql.com/) - Database server
- [phpMyAdmin](https://www.phpmyadmin.net/) - Database management tool
- [Docker](https://www.docker.com/) - Containerization platform

---

⭐ If you find this project helpful, please give it a star!

Made with ❤️ using Docker and WordPress
