// modules for the vcf workflow

process vcfmix {

    tag {sample_name}

    publishDir "${params.output_dir}/${sample_name}/output_vcfs", mode: 'copy', pattern: '*.json', overwrite: 'true'

    input:
    tuple val(sample_name), path(vcf)

    output:
    tuple val(sample_name), path("${sample_name}_f-stats.json"), emit: vcfmix_json

    script:
    bcftools_vcf = "${sample_name}.bcftools.vcf"

    """
    python3 ${baseDir}/bin/vcfmix.py ${bcftools_vcf}
    """

    stub:
    bcftools_vcf = "${sample_name}.bcftools.vcf"

    """
    touch ${bcftools_vcf}
    """
}
