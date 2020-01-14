#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import pandas as pd
import glob

##### Load config and sample sheets #####

configfile: "config/config.yaml"

samples = pd.read_table(config["samples"])

onsuccess:
	print("Workflow completed successfully!")

##### Define rules #####
rule all:
	input:
		# countLigationsOut1 = expand('output/{prefix}_countLigations_split{sample}_norm.txt.res.txt', prefix=config["prefix"], sample=samples.index),
		# countLigationsOut2 = expand('output/{prefix}_countLigations_split{sample}_linecount.txt', prefix=config["prefix"], sample=samples.index),
		# alignOut1 = expand('output/{prefix}_align_split{sample}.sam', prefix=config["prefix"], sample=samples.index),
		# handleChimerasOutAll = expand('output/{prefix}_align_split{sample}_{extension}', prefix=config["prefix"], sample=samples.index, extension=['norm.txt', 'alignable.sam', 'collisions.sam', 'collisions_low_mapq.sam', 'unmapped.sam', 'mapq0.sam', 'unpaired.sam']),
		# fragmentOutAll = expand("output/{prefix}_fragment_split{sample}.frag.txt", prefix=config["prefix"], sample=samples.index),
		# sam2bamOutAll = expand('output/{prefix}_sam2bam_split{sample}_{extension}.bam', prefix=config["prefix"], sample=samples.index, extension=['alignable', 'collisions', 'collisions_low_mapq', 'unmapped', 'mapq0', 'unpaired']),
		# sortOutAll = expand('output/{prefix}_sort_split{sample}.sort.txt', prefix=config["prefix"], sample=samples.index),
		mergeOutAll = expand('output/{prefix}_merge_{extension}.bam', prefix=config["prefix"], extension=['collisions', 'collisions_low_mapq', 'unmapped', 'mapq0']),
		# mergedSortOutAll = expand('output/{prefix}_mergedSort_merged_sort.txt', prefix=config["prefix"]),
		# dedupOutAll = expand('output/{prefix}_dedup_{extension}.txt', prefix=config["prefix"], extension=['dups', 'merged_nodups', 'opt_dups']),
		# dedupAlignablePart1 = expand('output/{prefix}_align_split{sample}_dedup', prefix=config["prefix"], sample=samples.index),
		# dedupAlignablePart2 = expand('output/{prefix}_align_split{sample}_{extension}', prefix=config["prefix"], sample=samples.index, extension=['alignable_dedup.sam', 'alignable.bam']),
		dedupAlignablePart3 = expand('output/{prefix}_dedupAlignablePart3_alignable.bam', prefix=config["prefix"]),
		statsOutAll = expand('output/{prefix}_dupStats_stats_dups{extension}', prefix=config["prefix"], extension=['.txt', '_hists.m']),
		interOutAll = expand('output/{prefix}_inter.txt', prefix=config["prefix"]),
		inter30OutAll = expand('output/{prefix}_inter_30.txt', prefix=config["prefix"])

## COUNT LIGATIONS, ALIGN FASTQ, HANDLE CHIMERIC READS, SORT BY READNAME
rule countLigations:
	input:
		R1 = lambda wildcards: samples.iloc[[int(i) for i in wildcards.sample]]["Read1"],
		R2 = lambda wildcards: samples.iloc[[int(i) for i in wildcards.sample]]["Read2"]
	output:
		temp = temp('output/{prefix}_countLigations_split{sample}_temp'),
		res = 'output/{prefix}_countLigations_split{sample}_norm.txt.res.txt',
		linecount = 'output/{prefix}_countLigations_split{sample}_linecount.txt'
	log:
		err = "output/logs/{prefix}_countLigations_split{sample}.err",
		out = "output/logs/{prefix}_countLigations_split{sample}.out"
	params:
		ligation = config['countLigations']['ligation']
	run:
		shell("R1={input.R1} R2={input.R2} ligation={params.ligation} temp={output.temp} res={output.res} linecount={output.linecount} ./scripts/countLigations.sh 2> {log.err} 1> {log.out}")
		# shell("R1={input.R1} R2={input.R2} ligation={params.ligation} res={output.res} linecount={output.linecount} ./scripts/countLigations.sh 2> {log.err} 1> {log.out}")

rule align:
	input:
		R1 = lambda wildcards: samples.iloc[[int(i) for i in wildcards.sample]]["Read1"],
		R2 = lambda wildcards: samples.iloc[[int(i) for i in wildcards.sample]]["Read2"]
	output:
		sam = "output/{prefix}_align_split{sample}.sam" ## Make temporary
	log:
		err = "output/logs/{prefix}_align_split{sample}.err"
	threads: 10
	params:
		fasta = config['fasta']
	run:
		shell("bwa mem -SP5M -t {threads} {params.fasta} {input.R1} {input.R2} > {output.sam} 2> {log.err}")

rule chimera:
	input:
		sam = rules.align.output.sam
	output:
		norm = "output/{prefix}_align_split{sample}_norm.txt",
		alignable = "output/{prefix}_align_split{sample}_alignable.sam", ## Make temporary
		collisions = "output/{prefix}_align_split{sample}_collisions.sam", ## Make temporary
		lowqcollisions = "output/{prefix}_align_split{sample}_collisions_low_mapq.sam", ## Make temporary
		unmapped = "output/{prefix}_align_split{sample}_unmapped.sam", ## Make temporary
		mapq0 = "output/{prefix}_align_split{sample}_mapq0.sam", ## Make temporary
		unpaired = "output/{prefix}_align_split{sample}_unpaired.sam" ## Make temporary
	threads: 10
	params:
		fname = 'output/{prefix}_align_split{sample}',
		mapq0_reads_included = config['chimera']['mapq0_reads_included']
	run:
		shell('touch {output}'),
		shell('gawk -v "fname"={params.fname} -v "mapq0_reads_included"={params.mapq0_reads_included} -f ./scripts/chimeric_blacklist.awk {input.sam}')

rule fragment:
	input:
		norm = rules.chimera.output.norm
	output:
		frag = "output/{prefix}_fragment_split{sample}.frag.txt",
	threads: 10
	params:
		site = config['site'],
		site_file = config['site_file']
	shell: ## Use better error handling with the if/else statement for restriction site
		"""
		if [ {params.site} != "none" ]
		then
				./scripts/fragment.pl {input.norm} {output.frag} {params.site_file}    
		else
				awk '{{printf("%s %s %s %d %s %s %s %d", $1, $2, $3, 0, $4, $5, $6, 1); for (i=7; i<=NF; i++) {{printf(" %s",$i);}}printf("\n");}}' {input.norm} > {output.frag}
		fi
		"""

rule sam2bam:
	input:
		lambda wildcards: ['output/{prefix}_align_split{sample}_{extension}.sam'.format(prefix=wildcards.prefix, sample=wildcards.sample, extension=wildcards.extension)]
	output:
		'output/{prefix}_sam2bam_split{sample}_{extension}.bam'
	run:
		shell('samtools view -hb {input} > {output}')

rule sort:
	input:
		rules.fragment.output.frag
	output:
		sorted = "output/{prefix}_sort_split{sample}.sort.txt"
	threads: 10
	shadow: "minimal"
	run:
		shell('sort -k2,2d -k6,6d -k4,4n -k8,8n -k1,1n -k5,5n -k3,3n {input} > {output.sorted}')

## MERGE SORTED AND ALIGNED FILES
rule merge:
	input:
		lambda wildcards: expand('output/{prefix}_sam2bam_split{sample}_{extension}.bam', prefix=config["prefix"], sample=samples.index, extension=wildcards.extension)
	output:
		'output/{prefix}_merge_{extension}.bam'
	log:
		err = "output/logs/{prefix}_merge_{extension}.err"
	threads: 10
	run:
		shell('samtools merge -n {output} {input} 2> {log.err}')

rule mergedSort:
	input:
		expand('output/{prefix}_sort_split{sample}.sort.txt', prefix=config["prefix"], sample=samples.index)
	output:
		'output/{prefix}_mergedSort_merged_sort.txt'
	threads: 10
	shadow: "minimal"
	run:
		shell('sort -m -k2,2d -k6,6d -k4,4n -k8,8n -k1,1n -k5,5n -k3,3n {input} > {output}')

## REMOVE DUPLICATES
rule dedup:
	input:
		rules.mergedSort.output
	output:
		dups = "output/{prefix}_dedup_dups.txt",
		merged_nodups = "output/{prefix}_dedup_merged_nodups.txt",
		optdups = "output/{prefix}_dedup_opt_dups.txt"
	params:
		name = 'output/{prefix}_'
	threads: 10
	run:
		shell('touch {output}'),
		shell('awk -f ./scripts/dups.awk -v name={params.name} {input}')

rule dedupAlignablePart1:
	input:
		rules.dedup.output.merged_nodups
	output:
		'output/{prefix}_align_split{sample}_dedup' ## Make temporary
	threads: 10
	shell:
		"""
		awk '{{split($(NF-1), a, "$"); split($NF, b, "$"); print a[3],b[3] > a[2]"_dedup"}}' {input}
		"""
rule dedupAlignablePart2:
	input:
		dedup = rules.dedupAlignablePart1.output,
		alignable = rules.chimera.output.alignable
	output:
		dedup_sam = 'output/{prefix}_align_split{sample}_alignable_dedup.sam',
		bam = 'output/{prefix}_align_split{sample}_alignable.bam'
	threads: 10
	shell:
		"""
		awk 'BEGIN{{OFS="\t"}}FNR==NR{{for (i=$1; i<=$2; i++){{a[i];}} next}}(!(FNR in a) && $1 !~ /^@/){{$2=or($2,1024)}}{{print}}' {input.dedup} {input.alignable} > {output.dedup_sam}
		samtools view -hb {input.alignable} > {output.bam}
		"""

rule dedupAlignablePart3:
	input:
		lambda wildcards: expand('output/{prefix}_align_split{sample}_alignable.bam', prefix=config["prefix"], sample=samples.index)
	output:
		'output/{prefix}_dedupAlignablePart3_alignable.bam'
	log:
		err = "output/logs/{prefix}_dedupAlignablePart3_alignable.err"
	threads: 10
	run:
		shell('samtools merge -n {output} {input} 2> {log.err}')

## STATISTICS
rule dupStats:
	input:
		rules.dedup.output.dups
	output:
		stats_dups = 'output/{prefix}_dupStats_stats_dups.txt',
		hists = 'output/{prefix}_dupStats_stats_dups_hists.m'
	params:
		site = config['site'],
		site_file = config['site_file']
	threads: 10
	run:
		shell('./scripts/statistics.pl -s {params.site_file} -l {params.site} -o {output.stats_dups} {input}')

rule inter:
	input:
		res = expand('output/{prefix}_countLigations_split{sample}_norm.txt.res.txt', prefix=config["prefix"], sample=samples.index),
		merged_nodups = rules.dedup.output.merged_nodups
	output:
		'output/{prefix}_inter.txt'
	params:
		site = config['site'],
		site_file = config['site_file']
	threads: 10
	shell:
		"""
		cat {input.res} | awk -f ./scripts/stats_sub.awk > {output}
		./scripts/juicer_tools LibraryComplexity output {output} >> {output}
		./scripts/statistics.pl -s {params.site_file} -l {params.site} -o {output} -q 1 {input.merged_nodups}
		"""

rule inter30:
	input:
		res = expand('output/{prefix}_countLigations_split{sample}_norm.txt.res.txt', prefix=config["prefix"], sample=samples.index),
		merged_nodups = rules.dedup.output.merged_nodups
	output:
		'output/{prefix}_inter_30.txt'
	params:
		site = config['site'],
		site_file = config['site_file']
	threads: 10
	shell:
		"""
		cat {input.res} | awk -f ./scripts/stats_sub.awk > {output}
		./scripts/juicer_tools LibraryComplexity output {output} >> {output}
		./scripts/statistics.pl -s {params.site_file} -l {params.site} -o {output} -q 30 {input.merged_nodups}
		"""