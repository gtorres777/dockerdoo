FROM python:3.7-slim-buster as base

USER root


ENV ODOO_VERSION ${ODOO_VERSION:-13.0}
# Library versions
ARG WKHTMLTOX_VERSION
ENV WKHTMLTOX_VERSION ${WKHTMLTOX_VERSION:-"0.12.5"}

ARG WKHTMLTOPDF_CHECKSUM
ENV WKHTMLTOPDF_CHECKSUM ${WKHTMLTOPDF_CHECKSUM:-"1140b0ab02aa6e17346af2f14ed0de807376de475ba90e1db3975f112fbd20bb"}

# Define Odoo directories         
ENV ODOO_DIR_BASEPATH=${ODOO_DIR_BASEPATH:-/opt/odoo_dir}    
ENV ODOO_BASEPATH=${ODOO_DIR_BASEPATH}/odoo

ENV ODOO_ADDONS_BASEPATH=${ODOO_BASEPATH}/addons \
    ODOO_CMD=${ODOO_BASEPATH}/odoo-bin \
    ODOO_EXTRA_ADDONS=${ODOO_DIR_BASEPATH}/repos \
    ODOO_EXTRA_DEV_ADDONS=${ODOO_DIR_BASEPATH}/repos_dev \
    ODOO_OCA_ADDONS=${ODOO_DIR_BASEPATH}/repos_oca \
    ODOO_NON_ENT_ADDONS=${ODOO_DIR_BASEPATH}/repos_non_ent

# Create Odoo user    
ARG APP_UID
ENV APP_UID ${APP_UID:-1000}
ARG APP_GID
ENV APP_GID ${APP_UID:-1000}
ENV ODOO_USER=odoo

RUN apt-get update \
    && addgroup --system --gid ${APP_GID} ${ODOO_USER} \
    && adduser --system --uid ${APP_UID} --ingroup ${ODOO_USER} --disabled-login --shell /sbin/nologin ${ODOO_USER} \
    # [Optional] Add sudo support for the non-root user & unzip for CI
    && apt-get install -y ssh sudo zip unzip \
    && echo ${ODOO_USER} ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/${ODOO_USER}\
    && chmod 0440 /etc/sudoers.d/${ODOO_USER} \
    #
    # Clean up
    && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
    && rm -rf /var/lib/apt/lists/*

# Install odoo deps
RUN set -x; \
    apt-get -qq update && apt-get -qq install -y --no-install-recommends \
    git-core \
    curl \
    fonts-liberation2 \
    dirmngr \
    fonts-noto-cjk \
    gnupg \
    locales \
    lsb-release \
    node-less \
    npm \
    python3-renderpm \
    python3-watchdog \
    nano \
    vim \
    zlibc \
    && curl -o wkhtmltox.deb -sSL https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/${WKHTMLTOX_VERSION}/wkhtmltox_${WKHTMLTOX_VERSION}-1.stretch_amd64.deb \
    && echo "${WKHTMLTOPDF_CHECKSUM} wkhtmltox.deb" | sha256sum -c - \
    && apt-get -qq update && apt-get install -y --no-install-recommends ./wkhtmltox.deb \
    && echo "deb http://packages.cloud.google.com/apt gcsfuse-$(lsb_release -cs) main" \
        | tee /etc/apt/sources.list.d/gcsfuse.list \
    && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - \
    && apt-get -qq update && apt-get install -y gcsfuse \
    && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
    && rm -rf /var/lib/apt/lists/* wkhtmltox.deb /tmp/*

# Install latest postgresql-client
RUN set -x; \
    echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > etc/apt/sources.list.d/pgdg.list \
    && export GNUPGHOME="$(mktemp -d)" \
    && repokey='B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8' \
    && gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "${repokey}" \
    && gpg --batch --armor --export "${repokey}" > /etc/apt/trusted.gpg.d/pgdg.gpg.asc \
    && gpgconf --kill all \
    && rm -rf "$GNUPGHOME" \
    && apt-get update  \
    && apt-get install -y postgresql-client-12 \
    && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
    && rm -rf /var/lib/apt/lists/*

# Install rtlcss (on Debian buster)
RUN set -x; \
    npm install -g rtlcss

# Install hard & soft build dependencies
RUN set -x; \
    apt-get -qq update && apt-get -qq install -y --no-install-recommends \
    apt-utils \
    apt-transport-https \
    build-essential \
    libfreetype6-dev \
    libfribidi-dev \
    libghc-zlib-dev \
    libharfbuzz-dev \
    libjpeg-dev \
    libgeoip-dev \
    libmaxminddb-dev \
    liblcms2-dev \
    libldap2-dev \
    libopenjp2-7-dev \
    libpq-dev \
    libsasl2-dev \
    libtiff5-dev \
    libwebp-dev \
    lsb-release \
    tcl-dev \
    && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
    && rm -rf /var/lib/apt/lists/* /tmp/*

USER ${ODOO_USER}
# Install other Odoo requirements
RUN set -x; \
    pip3.7 -qq install --no-cache-dir --upgrade \
    astor \
    black \
    geoip2 \
    ptvsd \
    psycogreen \
    python-magic \
    phonenumbers \
    num2words \
    qrcode \
    vobject \
    python-stdnum \
    click-odoo-contrib \
    inotify \
    python-json-logger \
    wdb \
    psutil==5.6.6 \
    psycopg2==2.8.3 \
    websocket-client \
    Werkzeug==0.15.6 \
    && sudo apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
    && sudo rm -rf /var/lib/apt/lists/* /tmp/*

# Odoo Configuration file defaults
ENV \
    ADMIN_PASSWORD=${ADMIN_PASSWORD:-my-weak-password} \
    ODOO_DATA_DIR=${ODOO_DATA_DIR:-/var/lib/odoo/data} \
    DB_PORT_5432_TCP_ADDR=${DB_PORT_5432_TCP_ADDR:-db} \
    DB_MAXCONN=${DB_MAXCONN:-64} \
    DB_ENV_POSTGRES_PASSWORD=${DB_ENV_POSTGRES_PASSWORD:-odoo} \
    DB_PORT_5432_TCP_PORT=${DB_PORT_5432_TCP_PORT:-5432} \
    DB_SSLMODE=${DB_SSLMODE:-prefer} \
    DB_TEMPLATE=${DB_TEMPLATE:-template1} \
    DB_ENV_POSTGRES_USER=${DB_ENV_POSTGRES_USER:-odoo} \
    DBFILTER=${DBFILTER:-.*} \
    HTTP_INTERFACE=${HTTP_INTERFACE:-0.0.0.0} \
    HTTP_PORT=${HTTP_PORT:-8069} \
    LIMIT_MEMORY_HARD=${LIMIT_MEMORY_HARD:-2684354560} \
    LIMIT_MEMORY_SOFT=${LIMIT_MEMORY_SOFT:-2147483648} \
    LIMIT_TIME_CPU=${LIMIT_TIME_CPU:-60} \
    LIMIT_TIME_REAL=${LIMIT_TIME_REAL:-120} \
    LIMIT_TIME_REAL_CRON=${LIMIT_TIME_REAL_CRON:-0} \
    LIST_DB=${LIST_DB:-True} \
    LOG_DB=${LOG_DB:-False} \
    LOG_DB_LEVEL=${LOG_DB_LEVEL:-warning} \
    LOGFILE=${LOGFILE:-None} \
    LOG_HANDLER=${LOG_HANDLER:-:INFO} \
    LOG_LEVEL=${LOG_LEVEL:-info} \
    MAX_CRON_THREADS=${MAX_CRON_THREADS:-2} \
    PROXY_MODE=${PROXY_MODE:-False} \
    SERVER_WIDE_MODULES=${SERVER_WIDE_MODULES:-base,web} \
    SMTP_PASSWORD=${SMTP_PASSWORD:-False} \
    SMTP_PORT=${SMTP_PORT:-25} \
    SMTP_SERVER=${SMTP_SERVER:-localhost} \
    SMTP_SSL=${SMTP_SSL:-False} \
    SMTP_USER=${SMTP_USER:-False} \
    TEST_ENABLE=${TEST_ENABLE:-False} \
    UNACCENT=${UNACCENT:-False} \
    WITHOUT_DEMO=${WITHOUT_DEMO:-False} \
    WORKERS=${WORKERS:-0} \
    # Run tests for all the modules in the custom addons
    RUN_TESTS=${RUN_TESTS:-"0"}\
    # PIP auto-install requirements.txt (change value to "1" to auto-install)
    PIP_AUTO_INSTALL=${PIP_AUTO_INSTALL:-"0"} \
    # Define all needed directories
    ODOO_RC=${ODOO_RC:-/etc/odoo/odoo.conf} \
    ODOO_DATA_DIR=${ODOO_DATA_DIR:-/var/lib/odoo/data} \
    ODOO_LOGS_DIR=${ODOO_LOGS_DIR:-/var/lib/odoo/logs} \
    # Python libries path
    PYTHON_PATH=${PYTHON_PATH}:-/home/odoo/.local/lib/python3.7/site-packages

# Copy from build env
COPY ./resources/ /

# This is needed to fully build with modules and python requirements
RUN sudo mkdir -p ${ODOO_BASEPATH} ${ODOO_DATA_DIR} ${ODOO_LOGS_DIR} ${ODOO_EXTRA_ADDONS} ${ODOO_EXTRA_DEV_ADDONS} ${ODOO_OCA_ADDONS} ${ODOO_NON_ENT_ADDONS} /etc/odoo/ /usr/share/GeoIP/

# Copy custom modules from the custom folder, if any.
RUN sudo chown -R ${ODOO_USER}:${ODOO_USER} /entrypoint.sh /getaddons.py /upgrade.py /GeoLite2-City.mmdb ${ODOO_DATA_DIR} ${ODOO_LOGS_DIR} ${ODOO_BASEPATH} ${ODOO_EXTRA_ADDONS} ${ODOO_EXTRA_DEV_ADDONS} ${ODOO_OCA_ADDONS} ${ODOO_NON_ENT_ADDONS} /etc/odoo/ /usr/share/GeoIP/ \
    && sudo chmod u+x /entrypoint.sh /getaddons.py /upgrade.py /GeoLite2-City.mmdb \
    # Install GeoIP database
    && sudo mv /GeoLite2-City.mmdb /usr/share/GeoIP/ \
    # Move upgrade script where user odoo has permissions
    && sudo mv /upgrade.py /home/odoo/

# Use noninteractive to get rid of apt-utils message
ENV DEBIAN_FRONTEND=noninteractive

RUN sudo sed -i -e 's/# es_PE.UTF-8 UTF-8/es_PE.UTF-8 UTF-8/' /etc/locale.gen && \
    sudo dpkg-reconfigure --frontend=noninteractive locales && \
    sudo update-locale LANG=es_PE.UTF-8
ENV \
    LANG=es_PE.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=es_PE.UTF-8

# Clone Odoo repo and will be installed
RUN git clone --depth=1 -b ${ODOO_VERSION} https://github.com/odoo/odoo.git ${ODOO_BASEPATH} \
    && pip3.7 install -r ${ODOO_BASEPATH}/requirements.txt \
    && sudo ln -s ${ODOO_BASEPATH}/odoo-bin /usr/local/bin/odoo


# INSTALL AWSCLI

RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip" \
	&& unzip /tmp/awscliv2.zip -d /tmp \
	&& sudo /tmp/aws/install \
	&& aws --version \
	&& rm -rf /tmp/aws*


ENTRYPOINT ["/entrypoint.sh"]

CMD ["odoo"]

