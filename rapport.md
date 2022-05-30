---
lang: fr-FR
title: Rapport - algotex
subtitle: Rapport du compilateur algotex
author:
    - Rémi Labbé
date: Mai 2022
documentclass: report
toc: true
fontsize: 12
mainfont: Source Code Pro Medium
monofont: mononoki Nerd Font
---

# Rapport de développement

## Fonctionnalitées fournies

Le compilateur suit la specification demandée en implementant une partie des
instructions disponibles dans le package Algo.

La liste des instructions disponibles est la suivante:

- SET
- INCR
- DECR
- IF
- IF ELSE
- DOWHILE...OD
- DO...WHILEOD
- REPEAT...UNTIL
- DOFORI
- DOFORD
- DOFORIS
- DOFORDS
- CALL
- RETURN

Les instructions suivante sont ignorées:

- CUT
- BREAK
- COM
- ACT
- LABEL
- IN
- OUT
- AUX

Attention! Les instructions DOFOR{...} et DOFOREACH{...} contenant une condition sous forme de phrase 
produiront une erreur puisqu'elles ne peuvent pas etre implementées.

## Implementation

Les variables locales ont été developpées en utilisant la pile, ainsi une variable garde bien 
la meme valeur apres un appel recursif.

Cette facon de recuperer la valeur d'une variable dans la pile en prenant en point de référence 
le sommet de cette derniere à forcé la creation d'une variable globale appelée "offset". Cette variable
garde en mémoire le décalage qu'il y a entre la derniere variable dans la pile et le sommet. 
En effet la pile étant aussi utilisée pour stocker les expression en cours de calcul, il se peut qu'on ai besoin
d'acceder à une variable alors qu'une valeur temporaire est toujours au sommet de la pile.

L'algorithme à traduire est lu dans le fichier dont le nom est donne en premier paramatre de l'appel 
a algo2asm.

## Limitation

Je n'ai pas eu le temps d'implémenter plus d'instruction que celle listée ci-dessus mais j'espere pouvoir le faire bientot
 afin de compléter les fonctionnalitées en suivant la documentation du package ALGO.

Mon projet reste disponnible sur le GitHub afin de suivre les avancees futures.
[[Remi-labbe](https://github.com/Remi-labbe/algotex)]

## Conclusion

La réalisation de ce projet a été une experience tres enrichissante puisqu'utilisant des technologie que nous n'avions
 pas utilisées avant. J'ai été tres interessé par ce que j'ai decouvert pendant mon travail et compte y allouer plus
 de temps dans les jours à venir afin de le compléter.


# Manuel d'utilisation

Le fichier Latex contenant la fonction doit se trouver dans le repertoire d'execution des commandes suivantes.

## Lire une fonction

```bash
./algo2asm fonction.tex
```

## Executer une fonction

```bash
./run "\SIPRO{fonction}{arg1,arg2...}"
```

Cette commande produira en sortie le resultat de la fonction sans retour à la ligne.
