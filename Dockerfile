FROM centos/s2i-base-centos7

EXPOSE 8080

ENV PYTHON_VERSION=3.6 \
    PATH=$HOME/.local/bin/:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONIOENCODING=UTF-8 \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    PIP_NO_CACHE_DIR=off

ENV SUMMARY="Platform for building and running Python $PYTHON_VERSION applications" \
    DESCRIPTION="Python $PYTHON_VERSION available as container is a base platform for \
building and running various Python $PYTHON_VERSION applications and frameworks. \
Python is an easy to learn, powerful programming language. It has efficient high-level \
data structures and a simple but effective approach to object-oriented programming. \
Python's elegant syntax and dynamic typing, together with its interpreted nature, \
make it an ideal language for scripting and rapid application development in many areas \
on most platforms."

LABEL summary="$SUMMARY" \
      description="$DESCRIPTION" \
      io.k8s.description="$DESCRIPTION" \
      io.k8s.display-name="Python 3.6" \
      io.openshift.expose-services="8080:http" \
      io.openshift.tags="builder,python,python36,python-36,rh-python36" \
      com.redhat.component="python36-container" \
      name="centos/python-36-centos7" \
      version="1" \
      usage="s2i build https://github.com/sclorg/s2i-python-container.git --context-dir=3.6/test/setup-test-app/ centos/python-36-centos7 python-sample-app" \
      maintainer="SoftwareCollections.org <sclorg@redhat.com>"

RUN INSTALL_PKGS="rh-python36 rh-python36-python-devel rh-python36-python-setuptools rh-python36-python-pip nss_wrapper \
        httpd24 httpd24-httpd-devel httpd24-mod_ssl httpd24-mod_auth_kerb httpd24-mod_ldap \
        httpd24-mod_session atlas-devel gcc-gfortran libffi-devel libtool-ltdl enchant cronie" && \
    yum install -y centos-release-scl && \
    yum -y --setopt=tsflags=nodocs install --enablerepo=centosplus $INSTALL_PKGS && \
    rpm -V $INSTALL_PKGS && \
    # Remove centos-logos (httpd dependency) to keep image size smaller.
    rpm -e --nodeps centos-logos && \
    yum -y clean all --enablerepo='*'

# Copy the S2I scripts from the specific language image to $STI_SCRIPTS_PATH.
COPY ./s2i/bin/ $STI_SCRIPTS_PATH

# Copy crontab
COPY ./s2i/etc/ ${APP_ROOT}/etc/

# Copy repo data for hadoop packages
COPY ./repo_data/Cern-Hadoop-Components.repo /etc/yum.repos.d/
RUN yum install -y epel-release

# Copy kerberos conf
COPY ./conf/krb5.conf /etc/

# - Create a Python virtual environment for use by any application to avoid
#   potential conflicts with Python packages preinstalled in the main Python
#   installation.
RUN source scl_source enable rh-python36 && \
    virtualenv ${APP_ROOT} && \
    chown -R 1001:0 ${APP_ROOT} && \
    chown -R 1001:0 /usr/sbin/crond && \
    fix-permissions ${APP_ROOT} -P && \
    rpm-file-permissions

# Install hadoop and hadoop config
RUN yum install -y cern-hadoop-config \
    cern-hadoop-client \
    cern-hadoop-xrootd-connector \
    hadoop-bin \ 
    spark-bin

# Install kerberos
RUN yum install -y krb5-libs \
     krb5-devel \
     krb5-workstation \
     pam_krb5

# Using Supercronic for cron jobs    
ENV SUPERCRONIC_URL=https://github.com/aptible/supercronic/releases/download/v0.1.9/supercronic-linux-amd64 \
    SUPERCRONIC=supercronic-linux-amd64 \
    SUPERCRONIC_SHA1SUM=5ddf8ea26b56d4a7ff6faecdd8966610d5cb9d85

RUN curl -fsSLO "$SUPERCRONIC_URL" \
 && echo "${SUPERCRONIC_SHA1SUM}  ${SUPERCRONIC}" | sha1sum -c - \
 && chmod +x "$SUPERCRONIC" \
 && mv "$SUPERCRONIC" "/usr/local/bin/${SUPERCRONIC}" \
 && ln -s "/usr/local/bin/${SUPERCRONIC}" /usr/local/bin/supercronic

# Setting environment variables required for running rucio-opint-backend
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1
ENV PYTHONPATH=${APP_ROOT}/src:$PYTHONPATH
ENV DJANGO_SETTINGS_MODULE='rucio_opint_backend.apps.core.settings'

#Set JAVA_HOME
RUN echo export JAVA_HOME=$(readlink -f $(which java)) > /etc/profile.d/javaenv.sh
RUN chmod 0755 /etc/profile.d/javaenv.sh

# - In order to drop the root user, we have to make some directories world
#   writable as OpenShift default security model is to run the container
#   under random UID.
USER 1001

# Set the default CMD to print the usage of the language image.
CMD $STI_SCRIPTS_PATH/usage