// enable dsl2
nextflow.enable.dsl = 2

// import modules
include {vcfmix} from '../modules/vcfModules.nf' params(params)

// define workflow component
workflow vcf {

    take:
      clockwork_vcf


    main:

      vcfmix(clockwork_vcf)

}
