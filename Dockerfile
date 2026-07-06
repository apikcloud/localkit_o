FROM apik/odoo:19.0-20260515-enterprise

USER root

RUN if getent group 1000; then groupmod -g 1001 $(getent group 1000 | cut -d: -f1); fi && \
    if getent passwd 1000; then usermod -u 1001 $(getent passwd 1000 | cut -d: -f1); fi && \
    groupmod -g 1000 odoo && \
    usermod -u 1000 -g 1000 odoo

RUN ls -la .
RUN apt-get update && apt-get install -y --no-install-recommends git zip unzip build-essential bash-completion
# COPY requirements.txt .
# RUN pip3 install --no-cache-dir --break-system-packages --ignore-installed -r requirements.txt
RUN rm -rf /var/lib/apt/lists/*

# Install bash completion for odoo command
COPY odoo-completion.bash /etc/bash_completion.d/odoo
RUN chmod 644 /etc/bash_completion.d/odoo

RUN mkdir -p /var/lib/odoo/data/filestore /mnt/extra-addons /etc/odoo \
    && chown -R odoo:odoo /var/lib/odoo /mnt/extra-addons /etc/odoo

RUN echo "odoo ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
USER odoo

RUN source /etc/bash_completion && echo "source /etc/bash_completion" >> ~/.bashrc

EXPOSE 8069 8071 8072
