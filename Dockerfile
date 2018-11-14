# DOCKER-VERSION 1.12.3
FROM genomehubs/easy-mirror:18.10
MAINTAINER  Richard Challis/Lepbase contact@lepbase.org

ENV TERM xterm
ENV DEBIAN_FRONTEND noninteractive

USER root
RUN cpanm Tree::DAG_Node \
        IO::Unread \
        Text::LevenshteinXS \
        Math::SigFigs

RUN apt-get update && apt-get install -y parallel rename

WORKDIR /ensembl
USER eguser
ARG cachebuster=477adbe49
RUN git clone -b 18.10 --recursive https://github.com/genomehubs/easy-import

USER root
RUN mkdir /import
COPY startup.sh /import/
RUN chown -R eguser /import

USER eguser
WORKDIR /import
RUN mkdir blast && \
    mkdir conf && \
    mkdir download && \
    mkdir meta && \
    mkdir data
WORKDIR data

ENV PERL5LIB $PERL5LIB:/ensembl/easy-import/modules
ENV PERL5LIB $PERL5LIB:/ensembl/easy-import/gff-parser

CMD /import/startup.sh $FLAGS
