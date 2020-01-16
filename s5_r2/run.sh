#!/bin/bash

# This script is adapted from swbd Kaldi run.sh (https://github.com/kaldi-asr/kaldi/blob/master/egs/swbd/s5c/run.sh) and the older s5 (r1) version of this script

# Copyright 2018 Kaldi developers (see: https://github.com/kaldi-asr/kaldi/blob/master/COPYING)
# Copyright 2018 Language Technology, Universitaet Hamburg (author: Benjamin Milde)

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Set bash to 'debug' mode, it prints the commands (option '-x') and exits on :
# -e 'error', -u 'undefined variable', -o pipefail 'error in pipeline',
set -euxo pipefail

stage=0
use_BAS_dictionaries=false
add_swc_data=true
add_mailabs_data=true
add_extra_words=true

extra_words_file=local/extra_words.txt
extra_words_file=local/filtered_300k_vocab_de_wiki.txt

# TODO: missing data/local/dict/silence_phones.txt data/local/dict/optional_silence.txt data/local/dict/nonsilence_phones.txt ?

dict_suffix=_std

dict_dir=data/local/dict${dict_suffix}
local_lang_dir=data/local/lang${dict_suffix}
lang_dir=data/lang${dict_suffix}
lang_dir_nosp=${lang_dir}_nosp${dict_suffix}
format_lang_out_dir=${lang_dir}_test
g2p_dir=data/local/g2p${dict_suffix}
lm_dir=data/local/lm${dict_suffix}
arpa_lm=${lm_dir}/4gram-mincount/lm_pr10.0.gz

[ ! -L "steps" ] && ln -s ../../wsj/s5/steps
[ ! -L "utils" ] && ln -s ../../wsj/s5/utils
[ ! -L "rnnlm" ] && ln -s ../../../scripts/rnnlm/

. utils/parse_options.sh

if [ -f cmd.sh ]; then
      . cmd.sh; else
         echo "missing cmd.sh"; exit 1;
fi

if [ -f $sequitur_g2p ]
then
    echo "Using $sequitur_g2p for g2p conversion of OOV words."
else
    echo "Could not find g2p.py"
    echo "Please edit run.sh and point sequitur_g2p to the g2p.py python script of your Sequitur G2P installation."
    echo "Sequitur G2P can be downloaded from https://www-i6.informatik.rwth-aachen.de/web/Software/g2p.html"
    echo "E.g. wget https://www-i6.informatik.rwth-aachen.de/web/Software/g2p-r1668-r3.tar.gz"
    exit
fi

# mfccdir should be some place with a largish disk where you
# want to store MFCC features.
mfccdir=mfcc

utf8()
{
    iconv -f ISO-8859-1 -t UTF-8 $1 > $1.tmp
    mv $1.tmp $1
}

if [ $stage -le 1 ]; then
  # Prepares KALDI dir structure and asks you where to store mfcc vectors and the final models (both can take up significant space)
  python3 local/prepare_dir_structure.py

  if [ ! -d data/wav/german-speechdata-package-v2 ]
  then
      wget --directory-prefix=data/wav/ http://speech.tools/kaldi_tuda_de/german-speechdata-package-v2.tar.gz
      cd data/wav/
      tar xvfz german-speechdata-package-v2.tar.gz
      cd ../../
  fi

  if [ "$add_swc_data" = true ]; then
    
    echo "Adding SWC German data (see https://nats.gitlab.io/swc/)"    

    if [ ! -d data/wav/swc/german/ ]
    then
      mkdir -p data/wav/swc/
      wget --directory-prefix=data/wav/swc/ https://www2.informatik.uni-hamburg.de/nats/pub/SWC/SWC_German.tar
      cd data/wav/swc/
      tar xvf SWC_German.tar
      cd ../../../
    fi

# compute kaldi data dir from SWC export:   
#    if [ ! -d data/swc_train ]
#    then
#      wget --directory-prefix=data/ http://speech.tools/kaldi_tuda_de/swc_kaldi_data.tar.gz
#      cd data/
#      tar xvfz swc_kaldi_data.tar.gz
#      cd ../
#      python3 local/prepare_swc_german_wavscp.py
#    fi

# But the default is currently to download the precomputed SWC data dir (285h version, minimally pruned):
    if [ ! -d data/swc_train ]
    then
      wget --directory-prefix=data/ http://speech.tools/kaldi_tuda_de/swc_train_v2.tar.gz
      cd data/
      tar xvfz swc_train_v2.tar.gz
      cd ../
    fi

  fi

  if [ "$add_mailabs_data" = true ]
  then
    if [ ! -d data/wav/m_ailabs/ ]
    then
      mkdir -p data/wav/m_ailabs/
      wget --directory-prefix=data/wav/m_ailabs/ http://speech.tools/kaldi_tuda_de/m-ailabs.bayern.de_DE.tgz
      cd data/wav/m_ailabs/
      tar xvfz m-ailabs.bayern.de_DE.tgz
      cd ../../../
    fi
    if [ ! -d data/m_ailabs_train ]
    then
      # make data directory data/m_ailabs_train 
      python3 local/prepare_m-ailabs_data.py
    fi
  fi
fi

#adapt this to the Sprachdatenaufnahmen2014 folder on your disk
RAWDATA=data/wav/german-speechdata-package-v2

# Filter by name
FILTERBYNAME="*.xml"

if [ $stage -le 2 ]; then
  # Move files, which would later produce errors. They are saved in backup location
  python3 local/move_files_to_skip.py data/wav/german-speechdata-package-v2/train/

  find $RAWDATA/*/$FILTERBYNAME -type f > data/waveIDs.txt

  # prepares directories in Kaldi format for the TUDA speech corpus
  python3 local/data_prepare.py -f data/waveIDs.txt --separate-mic-dirs

  # If want to do experiments with very noisy data, you can also create Kaldi dirs for the Realtek microphone. Disabled in train/test/dev by default.
  # python3 local/data_prepare.py -f data/waveIDs.txt -p _Realtek -k _e

#   local/get_utt2dur_new.sh --read_entire_file=true data/tuda_train
  local/get_utt2dur.sh data/tuda_train
  if [ $? -ne 0 ]; then
    echo "Error at get_utt2dur.sh with TUDA corpus. Exiting."
    exit 1
  fi

  if [ "$add_swc_data" = false ] ; then
    mv data/tuda_train data/train
  fi
fi

if [ $stage -le 3 ]; then
  # Get freely available phoneme dictionaries, if they are not already downloaded
  if [ ! -f data/lexicon/de.txt ]
  then
      # this lexicon is licensed under LGPL
      wget --directory-prefix=data/lexicon/ https://raw.githubusercontent.com/marytts/marytts-lexicon-de/master/modules/de/lexicon/de.txt
  #    echo "data/lexicon/train.txt">> data/lexicon_ids.txt
      echo "data/lexicon/de.txt">> data/lexicon_ids.txt
  fi

  if [ use_BAS_dictionaries = true ] ; then

    # These lexicons are publicly available on BAS servers, but can probably not be used in a commercial setting.
    if [ ! -f data/lexicon/VM.German.Wordforms ]
    then
        wget --directory-prefix=data/lexicon/ ftp://ftp.bas.uni-muenchen.de/pub/BAS/VM/VM.German.Wordforms
        echo "data/lexicon/VM.German.Wordforms">> data/lexicon_ids.txt
    fi

    if [ ! -f data/lexicon/RVG1_read.lex ]
    then
        wget --directory-prefix=data/lexicon/ ftp://ftp.bas.uni-muenchen.de/pub/BAS/RVG1/RVG1_read.lex
        echo "data/lexicon/RVG1_read.lex">> data/lexicon_ids.txt
    fi

    if [ ! -f data/lexicon/RVG1_trl.lex ]
    then
        wget --directory-prefix=data/lexicon/ ftp://ftp.bas.uni-muenchen.de/pub/BAS/RVG1/RVG1_trl.lex
        echo "data/lexicon/RVG1_trl.lex">> data/lexicon_ids.txt
    fi

    if [ ! -f data/lexicon/LEXICON.TBL ]
    then
        wget --directory-prefix=data/lexicon/ ftp://ftp.bas.uni-muenchen.de/pub/BAS/RVG-J/LEXICON.TBL
        utf8 data/lexicon/LEXICON.TBL
        echo "data/lexicon/LEXICON.TBL">> data/lexicon_ids.txt
    fi
  fi
fi

if [ $stage -le 4 ]; then
  #Transform freely available dictionaries into lexiconp.txt file + extra files 
  mkdir -p ${dict_dir}/
  python3 local/build_big_lexicon.py -f data/lexicon_ids.txt -e data/local/combined.dict --export-dir ${dict_dir}/
  python3 local/export_lexicon.py -f data/local/combined.dict -o ${dict_dir}/_lexiconp.txt 
fi

g2p_model=${g2p_dir}/de_g2p_model
final_g2p_model=${g2p_model}-6

mkdir -p ${g2p_dir}/
#cp data_old/local/g2p/de_g2p_model-6 ${g2p_dir}/de_g2p_model-6

if [ $stage -le 5 ]; then
  train_file=${g2p_dir}/lexicon.txt
        
  cut -d" " -f 1,3- ${dict_dir}/_lexiconp.txt > $train_file
  cut -d" " -f 1 ${dict_dir}/_lexiconp.txt > ${g2p_dir}/lexicon_wordlist.txt
  
  if [ ! -f $final_g2p_model ]
  then
      mkdir -p ${g2p_dir}/

      $sequitur_g2p -e utf8 --train $train_file --devel 3% --write-model ${g2p_model}-1
      $sequitur_g2p -e utf8 --model ${g2p_model}-1 --ramp-up --train $train_file --devel 3% --write-model ${g2p_model}-2
      $sequitur_g2p -e utf8 --model ${g2p_model}-2 --ramp-up --train $train_file --devel 3% --write-model ${g2p_model}-3
      $sequitur_g2p -e utf8 --model ${g2p_model}-3 --ramp-up --train $train_file --devel 3% --write-model ${g2p_model}-4
      $sequitur_g2p -e utf8 --model ${g2p_model}-4 --ramp-up --train $train_file --devel 3% --write-model ${g2p_model}-5
      $sequitur_g2p -e utf8 --model ${g2p_model}-5 --ramp-up --train $train_file --devel 3% --write-model ${g2p_model}-6
  else
      echo "G2P model file $final_g2p_model already exists, not recreating it."
  fi

  if [ ! -f ${dict_dir}/oov_lexiconp.txt ]
  then
    echo "Now finding OOV in train"

    cp data/tuda_train/text ${g2p_dir}/complete_text

    if [ "$add_swc_data" = true ] ; then
      cat data/swc_train/text >> ${g2p_dir}/complete_text
    fi

    if [ "$add_mailabs_data" = true ] ; then
      cat data/m_ailabs_train/text >> ${g2p_dir}/complete_text
    fi

    if [ "$add_extra_words" = true ] ; then
      # source extra words from $extra_words_file (e.g. local/extra_words.txt) and prefix them with bogus ids, so that we can just add them to the transcriptions (${g2p_dir}/complete_text)
      gawk "{ printf(\"extra-word-%i %s\n\",NR,\$1) }" $extra_words_file | cat ${g2p_dir}/complete_text - > ${g2p_dir}/complete_text_new
      mv ${g2p_dir}/complete_text_new ${g2p_dir}/complete_text
    fi

    python3 local/find_oov.py -c ${g2p_dir}/complete_text -w ${g2p_dir}/lexicon_wordlist.txt -o ${g2p_dir}/oov.txt

    echo "Now using G2P to predict OOV"
    $sequitur_g2p -e utf8 --model $final_g2p_model --apply ${g2p_dir}/oov.txt > ${dict_dir}/oov_lexicon.txt
    cat ${dict_dir}/oov_lexicon.txt | gawk '{$1=$1" 1.0"; print }' > ${dict_dir}/_oov_lexiconp.txt
    # remove entries that don't have atleast 3 columns - some phonemizations are broken
    gawk 'NF>=3' ${dict_dir}/_oov_lexiconp.txt > ${dict_dir}/oov_lexiconp.txt
    #${dict_dir}/oov_lexicon.txt
    echo "Done!"
  else
    echo "OOV already predicted and exists, not recreating."
  fi
fi

# Now start preprocessing with KALDI scripts


# Path also sets LC_ALL=C for Kaldi, otherwise you will experience strange (and hard to debug!) bugs. It should be set here, after the python scripts and not at the beginning of this script
if [ -f path.sh ]; then
      . path.sh; else
         echo "missing path.sh"; exit 1;
fi

echo "Runtime configuration is: nJobs $nJobs, nDecodeJobs $nDecodeJobs. If this is not what you want, edit cmd.sh!"

# Make sure that LC_ALL is C for Kaldi, otherwise you will experience strange (and hard to debug!) bugs
# We set it here, because the Python data preparation scripts need a propoer utf local in LC_ALL
export LC_ALL=C
export LANG=C
export LANGUAGE=C

if [ $stage -le 6 ]; then
  # Sort the lexicon with C-encoding (Is this still needed?)
  sort -u ${dict_dir}/_lexiconp.txt ${dict_dir}/oov_lexiconp.txt > ${dict_dir}/lexiconp.txt

  # deleting lexicon.txt text from a previous run, utils/prepare_lang.sh will regenerate it
  if test -f "${dict_dir}/lexicon.txt"; then
    echo "${dict_dir}/lexicon.txt already exists, removing it..."
    rm ${dict_dir}/lexicon.txt || true
  fi

  unixtime=$(date +%s)
  # Move old lang dir if it exists
  mkdir -p ${lang_dir}/old_$unixtime/
  mv ${lang_dir}/* ${lang_dir}/old_$unixtime/ || true 
  # the fuck man

  echo "Preparing the ${lang_dir} directory...."

  # Prepare phoneme data for Kaldi
  utils/prepare_lang.sh ${dict_dir} "<UNK>" ${local_lang_dir} ${lang_dir}
  # optional silences needs linebreak how/why, currently seems just usb but only has 0 lines, adding line break with nano solves this.
  echo "Done!"
fi

# Todo: download source sentence archive for LM building

if [ $stage -le 7 ]; then
  mkdir -p ${lm_dir}/

  if [ ! -f ${lm_dir}/cleaned.gz ]
  then
      wget --directory-prefix=${lm_dir}/ http://speech.tools/kaldi_tuda_de/German_sentences_8mil_filtered_maryfied.txt.gz
      mv ${lm_dir}/German_sentences_8mil_filtered_maryfied.txt.gz ${lm_dir}/cleaned.gz
  fi

  # Prepare ARPA LM

  # If you wont to build your own:
  local/build_lm.sh --srcdir ${local_lang_dir} --dir ${lm_dir}

  # Otherwise you can also use the supplied LM:
  # wget speechdata-LM.arpa


  # Transform LM into Kaldi LM format 
  local/format_data.sh --arpa_lm $arpa_lm --lang_in_dir $lang_dir --lang_out_dir $format_lang_out_dir
fi

if [ "$add_swc_data" = true ] ; then
   if [ $stage -le 8 ]; then
      echo "Generating features for tuda_train, swc_train, dev and test"
      # Making sure all swc files are C-sorted 
      rm data/swc_train/spk2utt || true
      
      cat data/swc_train/segments | sort > data/swc_train/segments_sorted
      cat data/swc_train/text | sort | gawk 'NF>=2' > data/swc_train/text_sorted
      cat data/swc_train/utt2spk | sort > data/swc_train/utt2spk_sorted
      cat data/swc_train/wav.scp | sort > data/swc_train/wav.scp_sorted

      mv data/swc_train/wav.scp_sorted data/swc_train/wav.scp
      mv data/swc_train/utt2spk_sorted data/swc_train/utt2spk
      mv data/swc_train/text_sorted data/swc_train/text
      mv data/swc_train/segments_sorted data/swc_train/segments

      echo "$LC_ALL"

      utils/utt2spk_to_spk2utt.pl data/swc_train/utt2spk > data/swc_train/spk2utt      
      #utils/validate_data_dir.sh data/swc_train
      
      # Now make MFCC features.
      for x in swc_train tuda_train dev test; do
          utils/fix_data_dir.sh data/$x # some files fail to get mfcc for many reasons
          steps/make_mfcc.sh --cmd "$train_cmd" --nj $nJobs data/$x exp/make_mfcc/$x $mfccdir
          utils/fix_data_dir.sh data/$x # some files fail to get mfcc for many reasons
          steps/compute_cmvn_stats.sh data/$x exp/make_mfcc/$x $mfccdir
          utils/fix_data_dir.sh data/$x
      done
      echo "Done, now combining data (tuda_train swc_train)."
      ./utils/combine_data.sh data/train data/tuda_train data/swc_train
  fi
else
  if [ $stage -le 8 ]; then
    # Now make MFCC features.
    for x in train dev test; do
        utils/fix_data_dir.sh data/$x # some files fail to get mfcc for many reasons
        steps/make_mfcc.sh --cmd "$train_cmd" --nj $nJobs data/$x exp/make_mfcc/$x $mfccdir
        utils/fix_data_dir.sh data/$x # some files fail to get mfcc for many reasons
        steps/compute_cmvn_stats.sh data/$x exp/make_mfcc/$x $mfccdir
        utils/fix_data_dir.sh data/$x
    done
  fi
fi

if [ "$add_mailabs_data" = true ] ; then
  if [ $stage -le 8 ]; then
    mv data/train data/train_without_mailabs || true
    echo "Now computing MFCC features for m_ailabs_train"
    # Now make MFCC features.
    x=m_ailabs_train
    utils/fix_data_dir.sh data/$x # some files fail to get mfcc for many reasons
    steps/make_mfcc.sh --cmd "$train_cmd" --nj $nJobs data/$x exp/make_mfcc/$x $mfccdir
    utils/fix_data_dir.sh data/$x # some files fail to get mfcc for many reasons
    steps/compute_cmvn_stats.sh data/$x exp/make_mfcc/$x $mfccdir
    utils/fix_data_dir.sh data/$x
    
    echo "Done, now combining data (train m_ailabs_train)."
    ./utils/combine_data.sh data/train data/train_without_mailabs data/m_ailabs_train
  fi
fi
# Here we start the AM
# This is adapted from https://github.com/kaldi-asr/kaldi/blob/master/egs/swbd/s5c/run.sh

# check data/train/feats.scp available

if [ -f data/train/feats.scp ]; then
  echo "data/train/feats.scp is available, continuing with AM training."
else
  echo "data/train/feats.scp is not available, something went wrong in feature generation. Not continuing with AM training."
  exit -1
fi

if [ $stage -le 9 ]; then
  # Use the first 4k sentences as dev set.  Note: when we trained the LM, we used
  # the 1st 10k sentences as dev set, so the 1st 4k won't have been used in the
  # LM training data.   However, they will be in the lexicon, plus speakers
  # may overlap, so it's still not quite equivalent to a test set.
  utils/subset_data_dir.sh --first data/train 4000 data/train_dev # 5hr 6min
  
  # currently we do not have a  segments file as in swbd:
  if [ -f data/train/segments ]; then
    n=$[`cat data/train/segments | wc -l` - 4000]
  else
    n=$[`cat data/train/wav.scp | wc -l` - 4000]
  fi
  
  utils/subset_data_dir.sh --last data/train $n data/train_nodev

  # 55526 utterances in kaldi tuda de
  # (1/5 of swbd - 260k utterances)
  # we adapted the swbd numbers by dividing them by 5

  # original swbd comment:
  # Now-- there are 260k utterances (313hr 23min), and we want to start the
  # monophone training on relatively short utterances (easier to align), but not
  # only the shortest ones (mostly uh-huh).  So take the 100k shortest ones, and
  # then take 30k random utterances from those (about 12hr)

  # todo take this for no swbd training:
  utils/subset_data_dir.sh --shortest data/train_nodev 150000 data/train_100kshort #(swbd default: 100k)
  utils/subset_data_dir.sh data/train_100kshort 50000 data/train_30kshort #(swbd default: 30k)

  # Take the first 100k utterances (just under half the data); we'll use
  # this for later stages of training.
  utils/subset_data_dir.sh --first data/train_nodev 100000 data/train_100k

  # since there are more repetitions in kaldi-tuda-de compared to swbd, we upped the max repetitions a bit 200 -> 1000
  utils/data/remove_dup_utts.sh 1000 data/train_100k data/train_100k_nodup  # 110hr

  # Finally, the full training set:
  # since there are more repetitions in kaldi-tuda-de compared to swbd, we upped the max repetitions a bit 300 -> 1000
  utils/data/remove_dup_utts.sh 1000 data/train_nodev data/train_nodup  # 286hr

  # todo take this for no swbd training:
#  utils/subset_data_dir.sh --shortest data/train_nodev 30000 data/train_100kshort #(swbd default: 100k)
#  utils/subset_data_dir.sh data/train_100kshort 15000 data/train_30kshort #(swbd default: 30k)

  # Take the first 100k utterances (just under half the data); we'll use
  # this for later stages of training.
#  utils/subset_data_dir.sh --first data/train_nodev 40000 data/train_100k

  # since there are more repetitions in kaldi-tuda-de compared to swbd, we upped the max repetitions a bit 200 -> 1000
#  utils/data/remove_dup_utts.sh 2000 data/train_100k data/train_100k_nodup  # 110hr

  # Finally, the full training set:
  # since there are more repetitions in kaldi-tuda-de compared to swbd, we upped the max repetitions a bit 300 -> 1000
#  utils/data/remove_dup_utts.sh 2000 data/train_nodev data/train_nodup  # 286hr

  if [ ! -d ${lang_dir_nosp} ]; then 
    echo "Copying ${lang_dir} to ${lang_dir_nosp}..."
    cp -R ${lang_dir} ${lang_dir_nosp}
  fi
fi

if [ $stage -le 10 ]; then
  ## Starting basic training on MFCC features
  steps/train_mono.sh --nj $nJobs --cmd "$train_cmd" \
                      data/train_30kshort ${lang_dir_nosp} exp/mono
fi

if [ $stage -le 11 ]; then
    steps/align_si.sh --nj $nJobs --cmd "$train_cmd" \
                    data/train_100k_nodup ${lang_dir_nosp} exp/mono exp/mono_ali

    steps/train_deltas.sh --cmd "$train_cmd" \
                        3200 30000 data/train_100k_nodup ${lang_dir_nosp} exp/mono_ali exp/tri1

    graph_dir=exp/tri1/graph_nosp
    $train_cmd $graph_dir/mkgraph.log \
               utils/mkgraph.sh ${lang_dir}_test exp/tri1 $graph_dir
    
    for dset in dev test; do
        steps/decode_si.sh --nj $nDecodeJobs --num-threads 12 --cmd "$decode_cmd" --config conf/decode.config \
                       $graph_dir data/${dset} exp/tri1/decode_${dset}_nosp
    done
    
fi

if [ $stage -le 12 ]; then
  steps/align_si.sh --nj $nJobs --cmd "$train_cmd" \
                    data/train_100k_nodup ${lang_dir_nosp} exp/tri1 exp/tri1_ali

  steps/train_deltas.sh --cmd "$train_cmd" \
                        4000 70000 data/train_100k_nodup ${lang_dir_nosp} exp/tri1_ali exp/tri2

    # The previous mkgraph might be writing to this file.  If the previous mkgraph
    # is not running, you can remove this loop and this mkgraph will create it.
#    while [ ! -s ${lang_dir_nosp}_sw1_tg/tmp/CLG_3_1.fst ]; do sleep 60; done
#    sleep 20; # in case still writing.
    graph_dir=exp/tri2/graph_nosp
    $train_cmd $graph_dir/mkgraph.log \
               utils/mkgraph.sh ${lang_dir}_test exp/tri2 $graph_dir

    for dset in dev test; do
        steps/decode.sh --nj $nDecodeJobs  --num-threads 12 --cmd "$decode_cmd" --config conf/decode.config \
                    $graph_dir data/${dset} exp/tri2/decode_${dset}_nosp
    done
fi

if [ $stage -le 13 ]; then
  # The 100k_nodup data is used in the nnet2 recipe.
  steps/align_si.sh --nj $nJobs --cmd "$train_cmd" \
                    data/train_100k_nodup ${lang_dir_nosp} exp/tri2 exp/tri2_ali_100k_nodup

  # From now, we start using all of the data (except some duplicates of common
  # utterances, which don't really contribute much).
  steps/align_si.sh --nj $nJobs --cmd "$train_cmd" \
                    data/train_nodup ${lang_dir_nosp} exp/tri2 exp/tri2_ali_nodup

  # Do another iteration of LDA+MLLT training, on all the data.
  steps/train_lda_mllt.sh --cmd "$train_cmd" \
                          6000 140000 data/train_nodup ${lang_dir_nosp} exp/tri2_ali_nodup exp/tri3

  graph_dir=exp/tri3/graph_nosp
  $train_cmd $graph_dir/mkgraph.log \
             utils/mkgraph.sh ${lang_dir}_test exp/tri3 $graph_dir

  for dset in dev test; do
      steps/decode.sh --nj $nDecodeJobs  --num-threads 12 --cmd "$decode_cmd" --config conf/decode.config \
                  $graph_dir data/${dset} exp/tri3/decode_${dset}_nosp
  done
fi

if [ $stage -le 14 ]; then
  # Now we compute the pronunciation and silence probabilities from training data,
  # and re-create the lang directory.

  echo "Re-creating the lang directory with pronunciation and silence probabilities from training data"

  steps/get_prons.sh --cmd "$train_cmd" data/train_nodup ${lang_dir_nosp} exp/tri3
  utils/dict_dir_add_pronprobs.sh --max-normalize true \
                                  ${dict_dir} exp/tri3/pron_counts_nowb.txt exp/tri3/sil_counts_nowb.txt \
                                  exp/tri3/pron_bigram_counts_nowb.txt ${dict_dir}_pron

  utils/prepare_lang.sh ${dict_dir}_pron "<UNK>" ${local_lang_dir} ${lang_dir}

  ./local/format_data.sh --arpa_lm $arpa_lm --lang_in_dir $lang_dir --lang_out_dir ${lang_dir}_test_pron

  echo "Done. New lang dir in ${lang_dir}_test_pron"

#  LM=${lm_dir}/sw1.o3g.kn.gz
#  srilm_opts="-subset -prune-lowprobs -unk -tolower -order 3"
#  utils/format_lm_sri.sh --srilm-opts "$srilm_opts" \
#                         ${lang_dir} $LM ${dict_dir}/lexicon.txt ${lang_dir}_sw1_tg

#  LM=${lm_dir}/sw1_fsh.o4g.kn.gz
#  if $has_fisher; then
#    utils/build_const_arpa_lm.sh $LM ${lang_dir} ${lang_dir}_sw1_fsh_fg
#  fi

  graph_dir=exp/tri3/graph_pron
  $train_cmd $graph_dir/mkgraph.log \
             utils/mkgraph.sh ${lang_dir}_test_pron exp/tri3 $graph_dir
  
  for dset in dev test; do
      steps/decode.sh --nj $nDecodeJobs  --num-threads 12 --cmd "$decode_cmd" --config conf/decode.config \
                  $graph_dir data/${dset} exp/tri3/decode_${dset}_pron
  done
fi

# compile-train-graphs --read-disambig-syms=${lang_dir}/phones/disambig.int exp/tri3_ali_nodup/tree exp/tri3_ali_nodup/final.mdl ${lang_dir}/L.fst 'ark:utils/sym2int.pl --map-oov  -f 2- ${lang_dir}/words.txt data/train_nodup/split16/10/text|' 'ark:|gzip -c >exp/tri3_ali_nodup/fsts.10.gz' 
# the --map-oov option requires an argument at utils/sym2int.pl line 27.

if [ $stage -le 15 ]; then
  
  # Train tri4, which is LDA+MLLT+SAT, on all the (nodup) data.
  
  echo "Starting tri4 training, LDA+MLLT+SAT, on all the data"

  steps/align_fmllr.sh --nj $nJobs --cmd "$train_cmd" \
                       data/train ${lang_dir}_test_pron exp/tri3 exp/tri3_ali


  steps/train_sat.sh  --cmd "$train_cmd" \
                      11500 200000 data/train ${lang_dir} exp/tri3_ali exp/tri4

  graph_dir=exp/tri4/graph_pron
  $train_cmd $graph_dir/mkgraph.log \
             utils/mkgraph.sh ${lang_dir}_test_pron exp/tri4 $graph_dir

  for dset in dev test; do
      steps/decode_fmllr.sh --nj $nDecodeJobs  --num-threads 12 --cmd "$decode_cmd" \
                      --config conf/decode.config \
                      $graph_dir data/${dset} exp/tri4/decode_${dset}_pron
  done

  # Will be used for confidence calibration example,
  #steps/decode_fmllr.sh --nj $nJobs --cmd "$decode_cmd" \
  #                      $graph_dir data/train_dev exp/tri4/decode_dev_sw1_tg
  #if $has_fisher; then
  #  steps/lmrescore_const_arpa.sh --cmd "$decode_cmd" \
    #    ${lang_dir}_sw1_{tg,fsh_fg} data/eval2000 \
    #    exp/tri4/decode_eval2000_sw1_{tg,fsh_fg}
    #fi
 # ) &
fi

if [ $stage -le 16 ]; then
  echo "Cleanup the corpus"
  ./local/run_cleanup_segmentation.sh --langdir ${lang_dir} --nj $nJobs
fi

if [ $stage -le 17 ]; then
  echo "Now running TDNN chain data preparation, i-vector training and TDNN-HMM training"
  ./local/run_tdnn_1f.sh --lang_dir ${lang_dir} --stage 17
fi
