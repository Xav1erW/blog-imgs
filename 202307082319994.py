# train translator jp->zh based on MarianMT

import os
import torch
import torch.nn as nn
import torch.optim as optim

from tqdm import tqdm
import matplotlib.pyplot as plt
from transformers import AutoTokenizer, AutoModelForSeq2SeqLM, AdamW, get_linear_schedule_with_warmup, Seq2SeqTrainingArguments, Seq2SeqTrainer
import datasets
from transformers import DataCollatorForSeq2Seq

checkpoint = "X-Wang/pruned-mt5-small"
tokenizer = AutoTokenizer.from_pretrained(checkpoint)
model = AutoModelForSeq2SeqLM.from_pretrained(checkpoint)

# load dataset
dataset = datasets.load_dataset("X-Wang/Tatoeba-Challenge-v2021-08-07-ja-zh")

# tokenize dataset
def tokenize_function(examples):
    return tokenizer(examples["ja"], examples["zh"], truncation=True, padding="longest", max_length=128)

tokenized_dataset = dataset.map(tokenize_function, batched=True, num_proc=4, remove_columns=["ja", "zh"])

# split dataset
tokenized_dataset = tokenized_dataset.train_test_split(test_size=0.01)

# set training parameters
batch_size = 16
args = Seq2SeqTrainingArguments(
    "test-translation",
    evaluation_strategy = "epoch",
    learning_rate=2e-5,
    per_device_train_batch_size=batch_size,
    per_device_eval_batch_size=batch_size,
    weight_decay=0.01,
    save_total_limit=3,
    num_train_epochs=2,
    predict_with_generate=True,
    fp16=True,
)

# set trainer
data_collator = DataCollatorForSeq2Seq(tokenizer, model=model)
trainer = Seq2SeqTrainer(
    model,
    args,
    train_dataset=tokenized_dataset["train"],
    eval_dataset=tokenized_dataset["test"],
    data_collator=data_collator,
    tokenizer=tokenizer,
)