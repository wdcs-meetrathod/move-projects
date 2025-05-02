script {
    use de_fund_deposit::FundDeposit;

    fun main(admin: &signer){
        FundDeposit::init_registry(admin);
    }
}