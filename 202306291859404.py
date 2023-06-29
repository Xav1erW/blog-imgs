# import gradio as gr
from CliBert import CliBert
import torch
from torch.nn.functional import softmax
import os
import pandas as pd
from transformers import  AutoTokenizer, AutoModelForSeq2SeqLM
from transformers import pipeline
from lime.lime_text import LimeTextExplainer
from tqdm import tqdm
import jieba
from config import load_config
import time
config_file = './config.yaml'
cfg = load_config(config_file)

device = cfg['APP']['MODEL']['INFERENCE']['DEVICE']
model = CliBert(24).to(device)
# model.load_state_dict(torch.load('./bert_noNER_distil.pth'))
model.load_state_dict(torch.load('./bert_distil_pretrained_aug2.pth'))
tokenizer = AutoTokenizer.from_pretrained("distilbert-base-uncased")
df = pd.read_csv('./Symptom2Disease.csv', delimiter=',', header=0)
tags = pd.factorize(df['label'])[1]

tokenizer_trans = AutoTokenizer.from_pretrained("Helsinki-NLP/opus-mt-zh-en")

model_trans = AutoModelForSeq2SeqLM.from_pretrained("Helsinki-NLP/opus-mt-zh-en").to(device)

def is_chinese(text):
    """
    判断文本是否为中文
    """
    for char in text:
        if u'\u4e00' <= char <= u'\u9fff':
            return True
    return False

def translate(text):
    """
    text: List[str]
    """
    model_trans.eval()
    with torch.no_grad():
        tokens = tokenizer_trans(text, padding='longest', truncation=True, return_tensors='pt')
        tokens['input_ids'] = tokens['input_ids'].to(device)
        tokens['attention_mask'] = tokens['attention_mask'].to(device)
        out = model_trans.generate(**tokens)
        result = tokenizer_trans.batch_decode(out, skip_special_tokens=True)
    return result

def get_prob(text):
    if is_chinese(text[0]):
        bs=cfg['APP']['EXPLAIN']['BATCH_SIZE']
        sub_lists = [text[i:i+bs] for i in range(0, len(text), bs)]
        translated = []
        print('translating')
        for t in tqdm(sub_lists):
            translated.extend(translate(t))
    else:
        translated = text
    # translated = [translated['translation_text'] for t in translated]
    token = tokenizer(translated, padding='max_length', truncation=True, max_length=512, return_tensors='pt')
    inputs = token['input_ids']
    print(inputs.shape)
    batch_size=cfg['APP']['EXPLAIN']['BATCH_SIZE']
    data_loader = torch.utils.data.DataLoader(token['input_ids'], batch_size=batch_size)
    index = 0
    with torch.no_grad(): # 关闭梯度计算
        outputs = []
        for batch in tqdm(data_loader):
            # 对每个批次进行推理
            out = model(batch.to(device))
            out = softmax(out, dim=1)
            outputs.append(out)
        outputs = torch.cat(outputs)
    return outputs.cpu().numpy()


exp = LimeTextExplainer(class_names=cfg['APP']['MODEL']['INFERENCE']['CLASS_NAMES'])
exp_zh = LimeTextExplainer(class_names=cfg['APP']['MODEL']['INFERENCE']['CLASS_NAMES'],split_expression=jieba.lcut)



def greet(name):
    if is_chinese(name) and len(name)>500:
        raise gr.Error("您输入的文本过长！")
    elif (not is_chinese(name)) and len(name.split())>500:
        raise gr.Error("Too long input!")
    elif is_chinese(name) and len(name)<=10:
        raise gr.Error("请更加清晰地描述您的症状")
    elif (not is_chinese(name)) and len(name.split())<=10:
        raise gr.Error("Please describe your symptoms more clearly")
    t1 = time.time()
    alert = gr.update(value="""""", visible=False)
    with torch.no_grad():
        if is_chinese(name):
            translated = translate([name])[0]
            # translated = translator(name)[0]['translation_text']
        else:
            translated = name
        print('TRANSLATED')
        print(translated)
        tokenized = tokenizer(translated, padding="max_length", truncation=True, max_length=512, return_tensors='pt')
        out = model(tokenized['input_ids'].to(device))
        out = softmax(out, dim=1)
        out = out.cpu().squeeze().numpy().tolist()
        if max(out) < cfg['APP']['DISPLAY']['UNTRUSTED_THRES']:
            alert = gr.update(value="""
            上述结果**不可信**，请谨慎选择
            """, visible=True)
            pass
        pred_label = out.index(max(out))
        print('predict: ', pred_label)
        if is_chinese(name):
            new_exp = exp_zh.explain_instance(name, get_prob, num_features=cfg['APP']['EXPLAIN']['NUM_FEATURES'], labels=(pred_label,), num_samples=cfg['APP']['EXPLAIN']['NUM_SAMPLES'])
        else:
            new_exp = exp.explain_instance(name, get_prob, num_features=cfg['APP']['EXPLAIN']['NUM_FEATURES'], labels=(pred_label,), num_samples=cfg['APP']['EXPLAIN']['NUM_SAMPLES'])
        exp_list = new_exp.as_list(label=pred_label)
        exp_dict= {pair[0]:pair[1] for i, pair in enumerate(exp_list)}
        print(exp_dict)
        scores = []
        if is_chinese(name):
            for w in jieba.lcut(name):
                score = exp_dict.get(w, 0)
                scores.append((w , score))
        else:
            for w in name.split():
                score = exp_dict.get(w, 0)
                scores.append((w+' ' , score))
        print(scores)
    t2 = time.time()
    print('response time:', t2-t1)
    return {tags[i]:out[i] for i in range(len(out))}, scores, alert

import gradio as gr
def update(name):
    return f"Welcome to Gradio, {name}!"


theme = gr.themes.Soft()
with gr.Blocks(theme=theme, css="#alert_md {text-align:center;} #alert_md p, #alert_md strong {color: red; font-size:16px}", title="智能诊断系统") as demo:
    gr.Markdown("""
    # 智能诊断系统
    Start typing below and then click **Run** to see the output.
    """)
    with gr.Row():
        inp = gr.Textbox(placeholder="描述你的病症")
        with gr.Column():
            out1 = gr.outputs.Label(num_top_classes=cfg['APP']['DISPLAY']['TOP_N'])
            out_alert = gr.Markdown('', visible=False, elem_id="alert_md")
    with gr.Column():
        # 可解释性分析输出
        gr.Markdown("""
        ## 可解释性分析
        输出了您描述中的症状与诊断结果的关联度
        """)
        out2 = gr.HighlightedText(
            label="Contribution",
            combine_adjacent=True,
            show_legend=True,
        )
    btn = gr.Button("Run")
    btn.click(fn=greet, inputs=inp, outputs=[out1, out2, out_alert])
demo.launch(share=True)