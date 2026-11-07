"""Gera os gráficos de assets/img a partir do banco DuckDB do projeto.
Uso (a partir da pasta do projeto): python scripts/gerar_graficos.py fraude.duckdb
Requer: duckdb, matplotlib. Pré-requisito: sql/00 e sql/01 executados."""
import duckdb, sys, pathlib, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch
c=duckdb.connect(sys.argv[1] if len(sys.argv)>1 else "fraude.duckdb", read_only=True)
OUT=pathlib.Path(__file__).resolve().parent.parent / "reports" / "figures"
OUT.mkdir(exist_ok=True)
BLUE="#2a78d6"; GRAY="#c9c8c0"; INK="#0b0b0b"; INK2="#52514e"; SURF="#fcfcfb"
plt.rcParams.update({"font.family":["Segoe UI","DejaVu Sans"],"font.size":11,"axes.edgecolor":"#d6d5cf","axes.labelcolor":INK2,
 "xtick.color":INK2,"ytick.color":INK2,"figure.facecolor":SURF,"axes.facecolor":SURF})
def base(title, sub):
    fig,ax=plt.subplots(figsize=(9,4.6),dpi=150)
    fig.text(0.06,0.94,title,fontsize=14,fontweight="bold",color=INK,ha="left")
    fig.text(0.06,0.885,sub,fontsize=10.5,color=INK2,ha="left")
    for s in ["top","right","left"]: ax.spines[s].set_visible(False)
    ax.yaxis.grid(True,color="#ecebe6",lw=0.8); ax.set_axisbelow(True); ax.tick_params(length=0)
    fig.subplots_adjust(top=0.80,left=0.07,right=0.98,bottom=0.16)
    return fig,ax
def media(ax,x=None,label=True):
    ax.axhline(5,color=INK2,lw=1,ls=(0,(4,3)),zorder=3)
    if label: ax.text(ax.get_xlim()[0]+0.05 if x is None else x,5.25,"média 5%",color=INK2,fontsize=9,ha="left",va="bottom",bbox=dict(fc=SURF,ec="none",pad=1))
def bars(ax,labels,vals,colors,fmt="{:.1f}%"):
    b=ax.bar(labels,vals,color=colors,width=0.68,edgecolor=SURF,linewidth=2)
    for r,v in zip(b,vals): ax.text(r.get_x()+r.get_width()/2,v+0.3,fmt.format(v).replace(".",","),ha="center",va="bottom",fontsize=9.5,color=INK,bbox=dict(fc=SURF,ec="none",pad=1),zorder=4)
    ax.set_ylabel("taxa de fraude (%)")

# 1 valor
r=c.sql("""select case when valor_compra<10 then '< R$10' when valor_compra<25 then 'R$10–25' when valor_compra<50 then 'R$25–50' when valor_compra<100 then 'R$50–100' when valor_compra<250 then 'R$100–250' when valor_compra<500 then 'R$250–500' else 'R$500+' end f, min(valor_compra) o, avg(fraude)*100 t from abt_fraude group by 1 order by 2""").fetchall()
fig,ax=base("Quanto maior o valor, maior o risco","Taxa de fraude por faixa de valor (tracejado = média de 5%). Compras ≥ R$ 250: 2,6% do volume, 49% do valor fraudado.")
bars(ax,[x[0] for x in r],[x[2] for x in r],[BLUE if x[1]>=250 else GRAY for x in r]); ax.set_ylim(0,17); media(ax,label=False)
fig.savefig(f"{OUT}/01_fraude_por_valor.png"); plt.close(fig)

# 2 documentos
r=c.sql("""select 'Documento 1\nentregue' l, avg(fraude)*100 from abt_fraude where entrega_doc_1=1
union all select 'Documento 1\nnão entregue', avg(fraude)*100 from abt_fraude where entrega_doc_1=0
union all select 'Documento 2\nnão solicitado', avg(fraude)*100 from abt_fraude where entrega_doc_2 is null
union all select 'Documento 2\naprovado (Y)', avg(fraude)*100 from abt_fraude where entrega_doc_2='Y'
union all select 'Documento 2\nrecusado (N)', avg(fraude)*100 from abt_fraude where entrega_doc_2='N'""").fetchall()
fig,ax=base("Documentação pendente é o sinal mais forte","Taxa de fraude conforme a entrega dos documentos 1 e 2.")
bars(ax,[x[0] for x in r],[x[1] for x in r],[GRAY,BLUE,GRAY,GRAY,BLUE]); ax.set_ylim(0,25); media(ax)
fig.savefig(f"{OUT}/02_fraude_por_documento.png"); plt.close(fig)

# 3 decis
r=c.sql("""with d as (select *, ntile(10) over (order by score_fraude_modelo) dec from abt_fraude) select dec, min(score_fraude_modelo), max(score_fraude_modelo), avg(fraude)*100 from d group by 1 order by 1""").fetchall()
fig,ax=base("O score atual não ordena o risco","Taxa de fraude por decil do score_fraude_modelo (1 = score mais baixo). Os decis 1–3 têm mais fraude que os 4–7.")
labels=[f"{x[0]}\n({x[1]}–{x[2]})" for x in r]
cols=[BLUE if x[0] in (1,2,3,10) else GRAY for x in r]
bars(ax,labels,[x[3] for x in r],cols); ax.set_ylim(0,24); media(ax); ax.set_xlabel("decil (faixa de score)")
ax.annotate("inversão: 21% das fraudes\nestão no score < 30",xy=(2,3.6),xytext=(3.2,13),fontsize=9.5,color=INK,arrowprops=dict(arrowstyle="-",color=INK2,lw=1))
fig.savefig(f"{OUT}/03_score_por_decil.png"); plt.close(fig)

# 4 hora
r=c.sql("select hour(data_compra) h, avg(fraude)*100 from abt_fraude group by 1 order by 1").fetchall()
fig,ax=base("Madrugada concentra mais risco","Taxa de fraude por hora da compra. Entre 0h e 4h a taxa é 12,3%, contra 4,8% no resto do dia.")
b=ax.bar([f"{x[0]}h" for x in r],[x[1] for x in r],color=[BLUE if x[0]<=4 else GRAY for x in r],width=0.72,edgecolor=SURF,linewidth=2)
ax.set_ylabel("taxa de fraude (%)"); ax.set_ylim(0,19); ax.tick_params(axis="x",labelsize=8.5); media(ax,x=8.6)
ax.text(2,17.6,"17,2%",ha="center",fontsize=9.5,color=INK)
fig.savefig(f"{OUT}/04_fraude_por_hora.png"); plt.close(fig)
print("ok")
