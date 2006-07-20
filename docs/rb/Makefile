TEXTFILES=ss.tex title.tex copyright.tex introduction.tex description.tex requirements.tex
BIBFILES=
PROGFILES=
SOURCES=
FIGURES=

.PHONY: all ss clean

all: ss.ps

ps: ss.ps

ss.ps: $(TEXTFILES) $(PROGFILES) $(FIGURES)
	pslatex ss
	pslatex ss
	dvips -o ss.ps ss

ss.bbl: $(TEXTFILES) $(BIBFILES)
	pslatex ss
	bibtex ss

%.tex: %.ada
	lgrind -i -lAda -o $@ $<

%.eps: %.fig
	fig2dev -L eps $< >$@

small: ss2.ps

ss2.ps: ss.ps
	psnup -pa4 -2 ss.ps ss2.ps

pdf: ss.pdf

ss.pdf: ss.ps
	ps2pdf -sPAPERSIZE=a4 ss.ps ss.pdf

clean:
	rm -f *.log
	rm -f *.aux
	rm -f *.dvi
	rm -f *.blg
	rm -f *.cb
	rm -f *.toc
	rm -f *~ 

veryclean: clean
	rm -f $(PROGFILES) ss.ps ss2.ps ss.pdf



