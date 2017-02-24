#!/bin/bash
# ./auto_import.sh -s -g -d heliconius_melpomene_hmel2_core_31_84_1

EIDIR=/ensembl/easy-import
DOWNLOADDIR=/import/download
BLASTDIR=/import/blast
CONFDIR=/import/conf
DATADIR=/import/data
IMPORTSEQ=0
PREPAREGFF=0
IMPORTGENE=0
VERIFY=0
IMPORTBLAST=0
IMPORTRM=0
IMPORTCEG=0
EXPORTJSON=0
EXPORTSEQ=0
INDEX=0
OVERINI="$CONFDIR/.overwrite.ini"

while getopts "spgvbrcjeid:o:" OPTION
do
  case $OPTION in
    s)  IMPORTSEQ=1;;      # import_sequences.pl
    p)  PREPAREGFF=1;;     # prepare_gff.pl
    g)  IMPORTGENE=1;;     # import_gene_models.pl
    v)  VERIFY=1;;         # verify_translations.pl
    b)  IMPORTBLAST=1;;    # import_blastp.pl; import_interproscan.pl
    r)  IMPORTRM=1;;       # import_repeatmasker.pl
    c)  IMPORTCEG=1;;      # import_cegma_busco.pl
    e)  EXPORTSEQ=1;;      # export_sequences.pl
    j)  EXPORTJSON=1;;     # export_json.pl
    i)  INDEX=1;;          # index_database.pl
    d)  DATABASE=$OPTARG;; # core database name
  esac
done

# check database has been specified
if [ -z ${DATABASE+x} ]; then
  echo "ERROR: database variable (-e DATABASE=dbname) has not been set"
  exit
fi

if ! [ -d $DATABASE ]; then
  mkdir -p $DATABASE
fi

cd $DATABASE

if ! [ -d log ]; then
  mkdir -p log
fi

# check if $OVERINI file exists
if ! [ -s $OVERINI ]; then
  OVERINI=
fi

# check main ini file exists
if ! [ -s $CONFDIR/$DATABASE.ini ]; then
  echo "ERROR: file $CONFDIR/$DATABASE.ini does not exist"
  exit
fi
INI=$CONFDIR/$DATABASE.ini
DISPLAY_NAME=$(awk -F "=" '/SPECIES.DISPLAY_NAME/ {print $2}' $INI | perl -pe 's/^\s*// and s/\s*$// and s/\s/_/g')
ASSEMBLY=${DISPLAY_NAME}_$(awk -F "=" '/ASSEMBLY.DEFAULT/ {print $2}' $INI | perl -pe 's/^\s*// and s/\s*$// and s/\s/_/g')

if ! [ $IMPORTSEQ -eq 0 ]; then
  echo "importing sequences"
  perl $EIDIR/core/import_sequences.pl $INI $OVERINI &> >(tee log/import_sequences.err)
fi

if ! [ $PREPAREGFF -eq 0 ]; then
  echo "preparing gff"
  perl $EIDIR/core/prepare_gff.pl $INI $OVERINI &> >(tee log/prepare_gff.err)
fi

if ! [ $IMPORTGENE -eq 0 ]; then
  echo "importing gene models"
  # make list of alt ini files
  ALTINI=""
  for file in $CONFDIR/$DATABASE.*.ini
  do
    if ! [[ $file == *"blastpinterpro"* ]]; then
      if ! [[ $file == *"cegmabusco"* ]]; then
        ALTINI="$ALTINI $file"
      fi
    fi
  done
  perl $EIDIR/core/import_gene_models.pl $INI $ALTINI $OVERINI &> >(tee log/import_gene_models.err)
fi

if ! [ $VERIFY -eq 0 ]; then
  echo "verifying import"
  perl $EIDIR/core/verify_translations.pl $INI $OVERINI &> >(tee log/verify_translations.err)
  cat summary/verify_translations.log >> log/verify_translations.err
fi

if ! [ $IMPORTBLAST -eq 0 ]; then
  echo "importing blastp/interproscan"
  BLASTPINI="$CONFDIR/$DATABASE.blastpinterproscan.ini"
  if ! [ -s $BLASTPINI ]; then
    # create ini file to fetch result files from download directory
    printf "[FILES]
  BLASTP = [ BLASTP $DOWNLOADDIR/blastp/${ASSEMBLY}_-_proteins.fa.blastp.uniprot_sprot.1e-10.gz ]
  IPRSCAN = [ IPRSCAN $DOWNLOADDIR/interproscan/${ASSEMBLY}_-_proteins.fa.interproscan.gz ]
[XREF]
  BLASTP = [ 2000 Uniprot/swissprot/TrEMBL UniProtKB/TrEMBL ]\n" > $BLASTPINI
  fi
  perl $EIDIR/core/import_blastp.pl $INI $BLASTPINI $OVERINI &> >(tee log/import_blastp.err)
  perl $EIDIR/core/import_interproscan.pl $INI $BLASTPINI $OVERINI &> >(tee log/import_interproscan.err)
fi

if ! [ $IMPORTRM -eq 0 ]; then
  echo "importing repeatmasker"
  RMINI="$CONFDIR/$DATABASE.repeatmasker.ini"
  if ! [ -s $RMINI ]; then
    # create ini file to fetch result files from download directory
    printf "[FILES]\n  REPEATMASKER = [ txt $DOWNLOADDIR/repeats/${ASSEMBLY}.repeatmasker.out.gz ]\n" > $RMINI
  fi
  perl $EIDIR/core/import_repeatmasker.pl $INI $RMINI $OVERINI &> >(tee log/import_repeatmasker.err)
fi

if ! [ $IMPORTCEG -eq 0 ]; then
  echo "importing cegma/busco"
  CEGINI="$CONFDIR/$DATABASE.cegmabusco.ini"
  if ! [ -s $CEGINI ]; then
    # create ini file to fetch result files from download directory
    printf "[FILES]
  CEGMA = [ txt $DOWNLOADDIR/cegma/${ASSEMBLY}_-_cegma.txt ]
  BUSCO = [ txt $DOWNLOADDIR/busco/${ASSEMBLY}_-_busco.txt ]\n" > $CEGINI
  fi
  perl $EIDIR/core/import_cegma_busco.pl $INI $CEGINI $OVERINI &> >(tee log/import_cegma_busco.err)
fi

if ! [ $EXPORTSEQ -eq 0 ]; then
  echo "exporting sequences"
  if ! [ -d $DOWNLOADDIR/sequence ]; then
    mkdir -p $DOWNLOADDIR/sequence
  fi
  perl $EIDIR/core/export_sequences.pl $INI $OVERINI &> >(tee log/export_sequences.err)
  cd exported
  LIST=`ls ${ASSEMBLY}_-_{scaffolds,cds,proteins}.fa`
  echo "$LIST"
  cd ../
  cp exported/${ASSEMBLY}_-_scaffolds.fa $BLASTDIR
  if [ -s exported/${ASSEMBLY}_-_cds.fa ]; then
    cp exported/${ASSEMBLY}_-_cds.fa $BLASTDIR
  fi
  if [ -s exported/${ASSEMBLY}_-_proteins.fa ]; then
    cp exported/${ASSEMBLY}_-_proteins.fa $BLASTDIR
  fi
  echo "$LIST" | parallel --no-notice perl -p -i -e '"s/^>(\S+)\s(\S+)\s(\S+)/>\${2}__\${3}__\$1/"' '$BLASTDIR/{}'
  gzip exported/*.fa
  mv exported/*.gz $DOWNLOADDIR/sequence/
  rm -rf exported
fi

if ! [ $EXPORTJSON -eq 0 ]; then
  echo "exporting json"
  if ! [ -d $DOWNLOADDIR/json ]; then
    mkdir -p $DOWNLOADDIR/json
    mkdir -p $DOWNLOADDIR/json/annotations
    mkdir -p $DOWNLOADDIR/json/assemblies
    mkdir -p $DOWNLOADDIR/json/meta
  fi
  perl $EIDIR/core/export_json.pl $INI $OVERINI &> >(tee log/export_json.err)
  echo "done"
  mv web/*.codon-usage.json $DOWNLOADDIR/json/annotations
  mv web/*.assembly-stats.json $DOWNLOADDIR/json/assemblies
  mv web/*.meta.json $DOWNLOADDIR/json/meta
  rm -rf web
fi

if ! [ $INDEX -eq 0 ]; then
  echo "indexing database"
  perl $EIDIR/core/index_database.pl $INI $OVERINI &> >(tee log/index_database.err)
fi

cd ../
