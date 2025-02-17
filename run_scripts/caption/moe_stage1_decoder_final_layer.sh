#!/usr/bin/env

# The port for communication. Note that if you want to run multiple tasks on the same machine,
# you need to specify different port numbers.
export MASTER_PORT=1051

log_dir=./moe_de_final_layer_stage1_logs
save_dir=./moe_de_final_layer_stage1_checkpoints
mkdir -p $log_dir $save_dir

bpe_dir=../../utils/BPE
user_dir=../../ofa_module

data_dir=../../dataset/caption_data
data=${data_dir}/caption_stage1_train.tsv,${data_dir}/caption_val.tsv
restore_file=./moe_de_final_layer_stage1_checkpoints/2_0.06_2500_1_2e-5/checkpoint_last.pt
selected_cols=0,4,2

task=caption
arch=ofa_moe_base
criterion=adjust_label_smoothed_moe_cross_entropy
label_smoothing=0.1
lr=2e-5
max_epoch=5
warmup_ratio=0.06
batch_size=8
update_freq=8
resnet_drop_path_rate=0.0
encoder_drop_path_rate=0.1
decoder_drop_path_rate=0.1
dropout=0.1
attention_dropout=0.0
max_src_length=80
max_tgt_length=20
num_bins=1000
patch_image_size=480
eval_cider_cached=${data_dir}/cider_cached_tokens/coco-valid-words.p
drop_worst_ratio=0.2
moe_gate_loss_wt=1
moe_combine_method="sum"
moe_second_expert_policy="all"
moe_normalize_expert_grad="sqrt_world_size"

for max_epoch in {5,}; do
  echo "max_epoch "${max_epoch}
  for warmup_ratio in {0.06,}; do
    echo "warmup_ratio "${warmup_ratio}
    for drop_worst_after in {2500,}; do
      echo "drop_worst_after "${drop_worst_after}

      log_file=${log_dir}/${max_epoch}"_"${warmup_ratio}"_"${drop_worst_after}"_"${moe_gate_loss_wt}"_"${lr}".log"
      save_path=${save_dir}/${max_epoch}"_"${warmup_ratio}"_"${drop_worst_after}"_"${moe_gate_loss_wt}"_"${lr}
      mkdir -p $save_path

      CUDA_VISIBLE_DEVICES=0 python3 -m torch.distributed.launch --nproc_per_node=1 --master_port=${MASTER_PORT} ../../train.py \
          $data \
          --selected-cols=${selected_cols} \
          --bpe-dir=${bpe_dir} \
          --user-dir=${user_dir} \
          --restore-file=${restore_file} \
          --save-dir=${save_path} \
          --task=${task} \
          --arch=${arch} \
          --criterion=${criterion} \
          --label-smoothing=${label_smoothing} \
          --batch-size=${batch_size} \
          --update-freq=${update_freq} \
          --encoder-normalize-before \
          --decoder-normalize-before \
          --share-decoder-input-output-embed \
          --share-all-embeddings \
          --layernorm-embedding \
          --patch-layernorm-embedding \
          --code-layernorm-embedding \
          --resnet-drop-path-rate=${resnet_drop_path_rate} \
          --encoder-drop-path-rate=${encoder_drop_path_rate} \
          --decoder-drop-path-rate=${decoder_drop_path_rate} \
          --dropout=${dropout} \
          --attention-dropout=${attention_dropout} \
          --weight-decay=0.01 --optimizer=adam --adam-betas="(0.9,0.999)" --adam-eps=1e-08 --clip-norm=0.0 \
          --lr-scheduler=polynomial_decay --lr=${lr} \
          --max-epoch=${max_epoch} --warmup-ratio=${warmup_ratio} \
          --log-format=simple --log-interval=10 \
          --fixed-validation-seed=7 \
          --no-epoch-checkpoints --keep-best-checkpoints=1 \
          --save-interval=1 --validate-interval=1 \
          --save-interval-updates=2000 --validate-interval-updates=2000 \
          --eval-cider \
          --eval-cider-cached-tokens=${eval_cider_cached} \
          --eval-args='{"beam":1,"max_len_b":16,"no_repeat_ngram_size":3}' \
          --best-checkpoint-metric=cider --maximize-best-checkpoint-metric \
          --max-src-length=${max_src_length} \
          --max-tgt-length=${max_tgt_length} \
          --find-unused-parameters \
          --freeze-encoder-embedding \
          --freeze-decoder-embedding \
          --add-type-embedding \
          --scale-attn \
          --scale-fc \
          --scale-heads \
          --moe-expert-count=4 \
          --moe-freq=0 \
          --encoder-moe-freq=0 \
          --decoder-moe-freq=6 \
          --moe-gating-use-fp32 \
          --moe-second-expert-policy=${moe_second_expert_policy} \
          --moe-normalize-gate-prob-before-dropping \
          --moe-top1-expert \
          --moe-normalize-expert-grad=${sqrt_world_size} \
          --use-moe-pad-mask \
          --disable-entangle \
          --num-bins=${num_bins} \
          --patch-image-size=${patch_image_size} \
          --drop-worst-ratio=${drop_worst_ratio} \
          --drop-worst-after=${drop_worst_after} \
          --fp16 \
          --fp16-scale-window=512 \
          --num-workers=0 > ${log_file} 2>&1
    done
  done
done