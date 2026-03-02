FROM apik/odoo:19.0-20260131-enterprise

USER root

RUN if getent group 1000; then groupmod -g 1001 $(getent group 1000 | cut -d: -f1); fi && \
    if getent passwd 1000; then usermod -u 1001 $(getent passwd 1000 | cut -d: -f1); fi && \
    groupmod -g 1000 odoo && \
    usermod -u 1000 -g 1000 odoo

RUN apt-get update && apt-get install -y --no-install-recommends \
    git zip unzip build-essential \
    && pip3 install --no-cache-dir --break-system-packages \
    pylint pylint-odoo black flake8 isort \
    pytest pytest-cov coverage \
    ipython ipdb pydevd-odoo \
    manifestoo click-odoo click-odoo-contrib pre-commit \
    odoo-module-migrator \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/lib/odoo/data/filestore /mnt/extra-addons /etc/odoo \
    && chown -R odoo:odoo /var/lib/odoo /mnt/extra-addons /etc/odoo

RUN echo "odoo ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
USER odoo

EXPOSE 8069 8071 8072