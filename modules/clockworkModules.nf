// modules for the clockwork workflow

process alignToRef {
    /**
    * @QCcheckpoint fail if insufficient number and/or quality of read alignments to the reference genome
    */

    tag { sample_name }
    label 'clockwork'
    label 'normal_cpu'
    label 'medium_memory'

    publishDir "${params.output_dir}/$sample_name/output_bam", mode: 'copy', overwrite: 'true', pattern: '*{.bam,.bam.bai,_alignmentStats.json}'
    publishDir "${params.output_dir}/$sample_name", mode: 'copy', overwrite: 'true', pattern: '*{_err.json,_report.json}'

    input:
    tuple val(sample_name), path(fq1), path(fq2), path(software_json), path(species_json), val(doWeAlign)

    when:
    doWeAlign =~ /NOW\_ALIGN\_TO\_REF\_${sample_name}/

    output:
    tuple val(sample_name), path("${sample_name}_report.json"), path("${sample_name}.bam"), path("${sample_name}.fa"), stdout, emit: alignToRef_bam
    path("${sample_name}.bam.bai", emit: alignToRef_bai)
    path("${sample_name}_alignmentStats.json", emit: alignToRef_json)
    path "${sample_name}_err.json", emit: alignToRef_log optional true
    tuple val(sample_name), path("${sample_name}_report.json"), emit: alignToRef_report

    script:
    bam = "${sample_name}.bam"
    bai = "${sample_name}.bam.bai"
    stats = "${sample_name}.stats"
    stats_json = "${sample_name}_alignmentStats.json"
    report_json = "${sample_name}_report.json"
    error_log = "${sample_name}_err.json"

    """
    ref_fa=\$(jq -r '.top_hit.file_paths.ref_fa' ${species_json})

    cp \${ref_fa} ${sample_name}.fa

    minimap2 -ax sr ${sample_name}.fa -t ${task.cpus} $fq1 $fq2 | samtools fixmate -m - - | samtools sort -T tmp - | samtools markdup --reference ${sample_name}.fa - minimap.bam

    java -jar /usr/local/bin/picard.jar AddOrReplaceReadGroups INPUT=minimap.bam OUTPUT=${bam} RGID=${sample_name} RGLB=lib RGPL=Illumina RGPU=unit RGSM=sample

    samtools index ${bam} ${bai}
    samtools stats ${bam} > ${stats}

    python3 ${baseDir}/bin/parse_samtools_stats.py ${bam} ${stats} > ${stats_json}
    python3 ${baseDir}/bin/create_final_json.py ${stats_json} ${species_json}

    cp ${sample_name}_report.json ${sample_name}_report_previous.json

    jq -s ".[0] * .[1]" ${software_json} ${sample_name}_report_previous.json > ${report_json}

    continue=\$(jq -r '.summary_questions.continue_to_clockwork' ${report_json})

    if [ \$continue == 'yes' ]; then printf "NOW_VARCALL_${sample_name}"; elif [ \$continue == 'no' ]; then echo '{"error":"insufficient number and/or quality of read alignments to the reference genome"}' | jq '.' > ${error_log} && jq -s ".[0] * .[1]" ${error_log} ${sample_name}_report_previous.json > ${report_json}; fi
    """

    stub:
    bam = "${sample_name}.bam"
    bai = "${sample_name}.bam.bai"
    stats = "${sample_name}.stats"
    stats_json = "${sample_name}_alignmentStats.json"
    out_json = "${sample_name}_report.json"
    error_log = "${sample_name}_err.json"

    """
    touch ${sample_name}.fa
    touch ${bam}
    touch ${bai}
    touch ${stats}
    touch ${stats_json}
    touch ${out_json}
    touch ${error_log}
    printf ${params.alignToRef_doWeVarCall}
    """
}

process callVarsMpileup {
    /**
    * @QCcheckpoint none
    */

    tag { sample_name }
    label 'clockwork'
    label 'normal_cpu'
    label 'low_memory'

    publishDir "${params.output_dir}/$sample_name/output_vcfs", mode: 'copy', pattern: '*.vcf'

    input:
    tuple val(sample_name), path(report_json), path(bam), path(ref), val(doWeVarCall)

    when:
    doWeVarCall =~ /NOW\_VARCALL\_${sample_name}/

    output:
    tuple val(sample_name), path("${sample_name}.bcftools.vcf"), emit: mpileup_vcf

    script:
    bcftools_vcf = "${sample_name}.bcftools.vcf"

    """
    bcftools mpileup -Ou -a 'INFO/AD' -f ${ref} ${bam} | bcftools call --threads ${task.cpus} -vm -O v -o ${bcftools_vcf}
    """

    stub:
    bcftools_vcf = "${sample_name}.bcftools.vcf"

    """
    touch ${bcftools_vcf}
    """
}

process callVarsCortex {
    /**
    * @QCcheckpoint none
    */

    tag { sample_name }
    label 'clockwork'
    label 'normal_cpu'
    label 'medium_memory'

    publishDir "${params.output_dir}/$sample_name/output_vcfs", mode: 'copy', pattern: '*.vcf'
    
    input:
    tuple val(sample_name), path(report_json), path(bam), path(ref), val(doWeVarCall)

    when:
    doWeVarCall =~ /NOW\_VARCALL\_${sample_name}/

    output:
    tuple val(sample_name), path("${sample_name}.cortex.vcf"), emit: cortex_vcf

    script:
    cortex_vcf = "${sample_name}.cortex.vcf"

    """
    ref_dir=\$(jq -r '.top_hit.file_paths.clockwork_ref_dir' ${report_json})

    cp -r \${ref_dir}/* .

    clockwork cortex . ${bam} cortex ${sample_name}
    cp cortex/cortex.out/vcfs/cortex_wk_flow_I_RefCC_FINALcombined_BC_calls_at_all_k.raw.vcf ${cortex_vcf}
    """

    stub:
    cortex_vcf = "${sample_name}.cortex.vcf"

    """
    touch ${cortex_vcf}
    """
}

process minos {
    /**
    * @QCcheckpoint check if top species is TB, if yes pass vcf to gnomonicus
    */

    tag { sample_name }
    label 'clockwork'
    label 'medium_memory'

    publishDir "${params.output_dir}/$sample_name/output_vcfs", mode: 'copy', pattern: '*.vcf'
    publishDir "${params.output_dir}/$sample_name", mode: 'copy', overwrite: 'true', pattern: '*{_err.json,_report.json}'

    input:
    tuple val(sample_name), path(report_json), path(bam), path(ref), val(doWeVarCall), path(cortex_vcf), path(bcftools_vcf)

    output:
    tuple val(sample_name), path(report_json), path(bam), path(ref), emit: minos_bam
    tuple val(sample_name), path("${sample_name}.minos.vcf"), stdout, emit: minos_vcf
    tuple val(sample_name), path("${sample_name}_report.json"), emit: minos_report
    path "${sample_name}_err.json", emit: minos_log optional true

    script:
    minos_vcf = "${sample_name}.minos.vcf"
    error_log = "${sample_name}_err.json"

    """
    awk '{print \$1}' ${ref} > ref.fa

    minos adjudicate --force --reads ${bam} minos ref.fa ${bcftools_vcf} ${cortex_vcf}
    cp minos/final.vcf ${minos_vcf}
    rm -rf minos

    top_hit=\$(jq -r '.top_hit.name' ${report_json})

    cp ${sample_name}_report.json ${sample_name}_report_previous.json

    if [[ \$top_hit =~ ^"Mycobacterium tuberculosis" ]]; then printf "CREATE_ANTIBIOGRAM_${sample_name}"; else echo '{"gnomonicus-warning":"sample is not TB so cannot produce antibiogram using gnomonicus"}' | jq '.' > ${error_log} && printf "no" && jq -s ".[0] * .[1]" ${error_log} ${sample_name}_report_previous.json > ${report_json}; fi
    """

    stub:
    minos_vcf = "${sample_name}.minos.vcf"
    error_log = "${sample_name}_err.json"

    """
    touch ${minos_vcf}
    touch ${error_log}
    printf ${params.minos_isSampleTB}
    """
}

process gvcf {
    /**
    * @QCcheckpoint none
    */

    tag { sample_name }
    label 'clockwork'
    label 'normal_cpu'
    label 'low_memory'

    publishDir "${params.output_dir}/$sample_name/output_fasta", mode: 'copy', pattern: '*.fa'
    publishDir "${params.output_dir}/$sample_name/output_vcfs", mode: 'copy', pattern: '*.vcf.gz'
    publishDir "${params.output_dir}/$sample_name", mode: 'copy', overwrite: 'true', pattern: '*{_err.json,_report.json}'

    input:
    tuple val(sample_name), path(report_json), path(bam), path(ref), val(doWeValCall), path(minos_vcf), val(isSampleTB)

    output:
    path("${sample_name}.gvcf.vcf.gz", emit: gvcf)
    path("${sample_name}.fa", emit: gvcf_fa)
    path "${sample_name}_err.json", emit: gvcf_log optional true
    path "${sample_name}_report.json", emit: gvcf_report optional true

    script:
    gvcf = "${sample_name}.gvcf.vcf"
    gvcf_fa = "${sample_name}.fa"
    error_log = "${sample_name}_err.json"

    """
    awk '{print \$1}' ${ref} > ref.fa

    samtools mpileup -ugf ref.fa ${bam} | bcftools call --threads ${task.cpus} -m -O v -o samtools_all_pos.vcf

    clockwork gvcf_from_minos_and_samtools ref.fa ${minos_vcf} samtools_all_pos.vcf ${gvcf}
    clockwork gvcf_to_fasta ${gvcf} ${gvcf_fa}

    rm samtools_all_pos.vcf
    gzip ${gvcf}

    cp ${sample_name}_report.json ${sample_name}_report_previous.json

    if [ ${params.vcfmix} == "no" ] && [ ${params.gnomonicus} == "no" ]; then echo '{"complete":"workflow complete without error"}' | jq '.' > ${error_log} && jq -s ".[0] * .[1]" ${error_log} ${sample_name}_report_previous.json > ${report_json}; fi
    """

    stub:
    gvcf = "${sample_name}.gvcf.vcf.gz"
    gvcf_fa = "${sample_name}.fa"
    error_log = "${sample_name}_err.json"

    """
    touch ${gvcf}
    touch ${gvcf_fa}
    touch ${error_log}
    """
}

