# Makefile for the SDD document

TEXTFILES=sdd.tex title.tex copyright.tex introduction.tex description.tex overview.tex toplevel.tex detailed.tex
BIBFILES=report.bib
PROGFILES=static_stack_analysis.tex
SOURCES=
FIGURES=overview-architecture.eps node-hierarchy.eps

.PHONY: all sdd clean

all: sdd.ps

ps: sdd.ps

sdd.ps: $(TEXTFILES) $(PROGFILES) $(FIGURES) sdd.bbl
	pslatex sdd
	pslatex sdd
	dvips -o sdd.ps sdd

sdd.bbl: $(TEXTFILES) $(BIBFILES)
	pslatex sdd
	bibtex sdd

%.tex: %.ada
	lgrind -i -lAda -o $@ $<

%.eps: %.fig
	fig2dev -L eps $< >$@

small: sdd2.ps

sdd2.ps: sdd.ps
	psnup -pa4 -2 sdd.ps sdd2.ps

pdf: sdd.pdf

sdd.pdf: sdd.ps
	ps2pdf -sPAPERSIZE=a4 sdd.ps sdd.pdf

clean:
	rm -f *.log
	rm -f *.aux
	rm -f *.dvi
	rm -f *.blg
	rm -f *.cb
	rm -f *.toc
	rm -f *~ 

veryclean: clean
	rm -f $(PROGFILES) sdd.ps sdd2.ps sdd.pdf



