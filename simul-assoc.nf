#!/usr/bin/env nextflow
/*
 * Authors       :
 *
 *
 *      Scott Hazelhurst
 *      Shaun Aron
 *      Rob Clucas
 *      Eugene de Beste
 *      Lerato Magosi
 *      Brandenburg Jean-Tristan
 *
 *  On behalf of the H3ABionet Consortium
 *  2015-2018
 *
 *
 * Description  : Nextflow pipeline for Wits GWAS and simulation data
 *
 */


//---- General definitions --------------------------------------------------//

import java.nio.file.Paths


def helps = [ 'help' : 'help' ]

allowed_params = ["input_dir","input_pat","output","output_dir","num_cores","mem_req","gemma","linear","logistic","chi2","fisher", "work_dir", "scripts", "max_forks", "high_ld_regions_fname", "sexinfo_available", "cut_het_high", "cut_het_low", "cut_diff_miss", "cut_maf", "cut_mind", "cut_geno", "cut_hwe", "pi_hat", "super_pi_hat", "f_lo_male", "f_hi_female", "case_control", "case_control_col", "phenotype", "pheno_col", "batch", "batch_col", "samplesize", "strandreport", "manifest", "idpat", "accessKey", "access-key", "secretKey", "secret-key", "region", "AMI", "instanceType", "instance-type", "bootStorageSize", "boot-storage-size", "maxInstances", "max-instances", "sharedStorageMount", "shared-storage-mount",  "big_time","thin"]

param_bolt=["bolt_ld_scores_col","bolt_ld_score_file","boltlmm", "bolt_covariates_type",  "bolt_use_missing_cov"]
allowed_params+=param_bolt
param_fastlmm=["fastlmm"]
allowed_params+=param_fastlmm
param_phenosim=["phs_nb_sim", "phs_qual", "ph_qual_dom", "ph_maf_r", "ph_alpha_lim", "ph_windows_size"]
allowed_params+=param_phenosim


params.each { parm ->
  if (! allowed_params.contains(parm.key)) {
    println "\nUnknown parameter : Check parameter <$parm>\n";
  }
}

def params_help = new LinkedHashMap(helps)

params.queue      = 'batch'
params.work_dir   = "$HOME/h3agwas"
params.input_dir  = "${params.work_dir}/input"
params.output_dir = "${params.work_dir}/output"
params.output_testing = "cleaned"
params.thin       = ""
params.covariates = ""
params.chrom      = ""
outfname = params.output_testing

supported_tests = ["chi2","fisher","model","cmh","linear","logistic","boltlmm", "fastlmm", "gemma"]


params.chi2     = 0
params.fisher   = 0
params.cmh     =  0
params.model   =  0
params.linear   = 0
params.logistic = 0
params.gemma = 0
params.mem_req = "6GB"
params.gemma_relopt = 1
params.gemma_lmmopt = 4

/*JT Append initialisation variable*/
params.bolt_covariates_type = ""
params.bolt_ld_score_file= ""
params.bolt_ld_scores_col=""
params.boltlmm = 0
params.bolt_use_missing_cov=0
params.num_cores=1
/*fastlmm param*/
params.fastlmm = 0
params.fastlmm_multi = 0

params.input_pat  = 'raw-GWA-data'

params.sexinfo_available = "false"

/*param for phenosim*/
/*Number simulation*/
params.phs_nb_sim=5
/*quantitative traits => 1
qualitative traits 0*/
params.phs_qual=1
/*Qualitative */
/*Nb qtl*/
params.phs_nb_qtl=2
/*qtl : number be as phs_nb_qtl, separate by ","*/
/*params.phs_list_qtl=([0.05]*params.phs_nb_qtl).join(",")
*/
params.phs_list_qtl=""
/*ph_qual_dom Quantitative : adititve : 0 dominant 1 */
params.ph_qual_dom=0
/*freq for each snps*/
params.ph_maf_r="0.05,1.0"
params.ph_alpha_lim="0.05,0.000001"
params.ph_windows_size="1000000bp"

params.help = false
if (params.help) {
    params.each {
    entry ->
      print "Parameter: <$entry.key>    \t Default: $entry.value"
      if (entry.key == 'help')
          println ""
      else {
        help = params_help.get(entry.key)
        if (help)
          print "\n    $help"
        println ""
      }
  }
  System.exit(-1)
}

def getConfig = {
  all_files = workflow.configFiles.unique()
  text = ""
  all_files.each { fname ->
      base = fname.baseName
      curr = "\n\n*-subsection{*-protect*-url{$base}}@.@@.@*-footnotesize@.@*-begin{verbatim}"
      file(fname).eachLine { String line ->
        if (line.contains("secretKey")) { line = "secretKey='*******'" }
        if (line.contains("accessKey")) { line = "accessKey='*******'" }
        curr = curr + "@.@"+line
      }
      curr = curr +"@.@*-end{verbatim}\n"
      text = text+curr
  }
  return text
}


// Checks if the file exists
checker = { fn ->
   if (fn.exists())
       return fn;
    else
       error("\n\n------\nError in your config\nFile $fn does not exist\n\n---\n")
}


if (params.thin)
   thin = "--thin ${params.thin}"
else
   thin = ""

if (params.chrom)
   chrom = "--chr ${params.chrom}"
else
   chrom = ""

/*Initialisation of bed data, check files exist*/
raw_src_ch= Channel.create()

bed = Paths.get(params.input_dir,"${params.input_pat}.bed").toString()
bim = Paths.get(params.input_dir,"${params.input_pat}.bim").toString()
fam = Paths.get(params.input_dir,"${params.input_pat}.fam").toString()

Channel
    .from(file(bed),file(bim),file(fam))
    .buffer(size:3)
    .map { a -> [checker(a[0]), checker(a[1]), checker(a[2])] }
    .set { raw_src_ch }


/*if need a chromosome or sub sample of data*/
bed_all_file_ms=Channel.create()
if (thin+chrom) {
  process thin {
    input:
      set file(bed), file(bim), file(fam) from raw_src_ch
    output:
      /*JT Append initialisation boltlmm_assoc_ch */
      set file("${out}.bed"), file("${out}.bim"), file("${out}.fam") into (bed_all_file_ms)
    script:
       base = bed.baseName
       out  = base+"_t"
       "plink --keep-allele-order --bfile $base $thin $chrom --make-bed --out $out"
  }
  }else{
        raw_src_ch.into(bed_all_file_ms)
 }


/*transform data in ms for phenosim*/

process ChangeMsFormat{
   cpus params.num_cores
   memory params.mem_req
   input :
     set file(bed), file(bim), file(fam) from bed_all_file_ms
   output :
     set file(data_ms), file(data_ms_ped), file(data_ms_bed), file(data_ms_bim), file(data_ms_fam) into phenosim_data 
     set file(data_ms_bed), file(data_ms_bim), file(data_ms_fam) into data_gemma_rel
   script :
     base=bed.baseName
     base_ped=base+"_ped"
     data_ms=base+".ms"
     data_ms_ped=data_ms+".ped"
     data_ms_map=data_ms+".map"
     data_ms_fam=data_ms+".fam"
     data_ms_bim=data_ms+".bim"
     data_ms_bed=data_ms+".bed"
     
     """
     plink --keep-allele-order --bfile $base --threads ${params.num_cores} --recode tab --out $base_ped
     convert_plink_ms.py $base_ped".ped" $bim $data_ms $data_ms_ped
     cp $base_ped".map"  $data_ms_map
     cp $base".fam"  $data_ms_fam
     cp $base".bim"  $data_ms_bim
     plink --keep-allele-order --file $data_ms --make-bed  --out $data_ms --threads ${params.num_cores}
     """
}

phenosim_data_all=Channel.from(1..params.phs_nb_sim).combine(phenosim_data)
if(params.phs_qual==1){
if(!params.phs_list_qtl)LQTL=([0.05]*params.phs_nb_qtl).join(",")
else LQTL=params.phs_list_qtl
phs_qual_param="-n ${params.phs_nb_qtl} -v $LQTL"
}
process SimulPheno{
   cpus params.num_cores
   memory params.mem_req
   input :
     set sim, file(ms), file(ped),file(bed), file(bim), file(fam) from phenosim_data_all
   output :
     set sim, file(file_causal), file(file_pheno), file(bed), file(bim), file(fam) into (sim_data_gemma,sim_data_bolt, sim_data_plink)
   script :
     base=bed.baseName
     ent_out_phen=base+"."+sim+".pheno"
     file_pheno=ent_out_phen+".pheno"
     file_causal=ent_out_phen+".causal"
     """
     phenosim.py -d 1 -f $ms -i M -o N -q ${params.phs_qual} $phs_qual_param --maf_c 0 --outfile $ent_out_phen
     echo -e "FID\\tIID\\tPhenoS" > $file_pheno
     paste $fam $ent_out_phen"0.pheno"|awk '{print \$1"\\t"\$2"\\t"\$NF}' >> $file_pheno
     ListePos=`awk 'BEGIN{AA=""}{AA=AA\$2","}END{print AA}' ${ent_out_phen}0.causal`
     get_lines_bynum.py --file $bim --lines \$ListePos --out ${file_causal}"tmp"
     paste ${file_causal}"tmp" ${ent_out_phen}0.causal > $file_causal
     """
}
if(params.gemma==1){

  process getGemmaRel {
    cpus params.num_cores
    memory params.mem_req
    time params.big_time
    input:
       file plinks from data_gemma_rel
    output:
       file("output/${base}.*XX.txt") into rel_mat_ch
    script:
       base = plinks[0].baseName
       """
       export OPENBLAS_NUM_THREADS=${params.gemma_num_cores}
       gemma -bfile $base  -gk ${params.gemma_relopt} -o $base
       """
  }
  sim_data_gemma2=sim_data_gemma.combine(rel_mat_ch)
  covariate_option=""
  process doGemma{
    cpus params.num_cores
    memory params.mem_req
    input:
      set sim, file(file_causal), file(file_pheno), file(bed), file(bim), file(fam), file(rel) from sim_data_gemma2
    output :
      set sim, file(file_causal), file("output/${out}.assoc.txt"), file(bim) into res_gem
    script :
       base = bed.baseName
       gemma_covariate=base+"."+sim+".cov"
       gemma_pheno=base+"."+sim+".phe"
       out=base+"."+sim+".gem"
       /*covar_opt_gemma    =  (params.covariates) ?  " -c $gemma_covariate " : ""*/
       covar_opt_gemma    = ""
       """
       all_covariate.py --data  $file_pheno --inp_fam  $fam $covariate_option --cov_out $gemma_covariate \
                          --pheno PhenoS --phe_out $gemma_pheno --form_out 1
       export OPENBLAS_NUM_THREADS=${params.gemma_num_cores}
       gemma -bfile $base ${covar_opt_gemma}  -k $rel -lmm 1  -n 1 -p $gemma_pheno  -o $out 
       """
   }
   alpha_lim=params.ph_alpha_lim
   process doGemmaStat{

    input:
      set sim, file(file_causal), file(stat), file(bim) from res_gem
    output :
      set sim, file(out) into res_stat_gem
    script :
      base=bim.baseName
      out=base+"."+sim+".res.stat"
      """
      compute_stat_phenosim.py --stat $stat --bim  $bim --header_pval p_wald --header_chro chr --header_pos ps --windows_size $params.ph_windows_size --alpha_lim $params.ph_alpha_lim --out $out --pos_simul $file_causal
      """
  }
  process MergeStatGemma{


  }


}

if(params.boltlmm==1){
   if(params.bolt_ld_score_file){
      ld_score_cmd="--LDscoresFile=$params.bolt_ld_score_file"
      if(params.bolt_ld_scores_col) ld_score_cmd = ld_score_cmd + " --LDscoresCol="+params.bolt_ld_scores_col
   } else
      ld_score_cmd = "--LDscoresUseChip"

   if (params.covariates)
      bolt_covariate= boltlmmCofact(params.covariates,params.bolt_covariates_type)
   else
      bolt_covariate= ""
  bolt_covariate=""
  type_lmm="--lmm"
  

  process doBoltlmmm{
    cpus params.num_cores
    memory params.mem_req
    input:
      set sim, file(file_causal), file(file_pheno), file(bed), file(bim), file(fam) from sim_data_bolt
    output :
      set sim, file(file_causal), file(out), file(bim) into res_bolt
    script :
       base = bed.baseName
       bolt_covariate=base+"."+sim+".cov"
       bolt_pheno=base+"."+sim+".phe"
       out=base+"."+sim+".bolt"
       /*covar_opt_bolt    =  (params.covariates) ?  " -c $bolt_covariate " : ""*/
       covar_opt_bolt    = ""
       """
       shuf -n 950000 $bim | awk '{print \$2}' > .sample.snp
       all_covariate.py --data  $file_pheno --inp_fam  $fam $covariate_option --cov_out $bolt_covariate \
                          --pheno PhenoS --phe_out $bolt_pheno --form_out 2
       bolt $type_lmm --bfile=$base  --phenoFile=$bolt_pheno --phenoCol=PhenoS --numThreads=$params.num_cores    --statsFile=$out\
           $ld_score_cmd  --lmmForceNonInf  --modelSnps=.sample.snp

       """
   }
   alpha_lim=params.ph_alpha_lim
   process doBoltStat{

    input:
      set sim, file(file_causal), file(stat), file(bim) from res_bolt
    output :
      set sim, file(out) into res_stat_bolt
    script :
      base=bim.baseName
      out=base+"."+sim+".res.stat"
      """
      compute_stat_phenosim.py --stat $stat --bim  $bim --header_pval P_BOLT_LMM_INF --header_chro CHR --header_pos BP --windows_size $params.ph_windows_size --alpha_lim $params.ph_alpha_lim --out $out --pos_simul $file_causal
      """

  }
}






