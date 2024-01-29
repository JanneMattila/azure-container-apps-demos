FROM mcr.microsoft.com/azure-cli:2.56.0

COPY init.sh /bin/
RUN chmod 755 /bin/init.sh

COPY run.sh /bin/
RUN chmod 755 /bin/run.sh

ENTRYPOINT ["/bin/init.sh", "/bin/run.sh"]
