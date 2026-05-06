 USE CATALOG medallion_demo;                                                                       
                                                                                                    
  -- Drop all 50 partial/slow gold MVs:                                                             
  DROP MATERIALIZED VIEW IF EXISTS team_pd_direct_lending.mvposition_analytics_fact;                
  DROP MATERIALIZED VIEW IF EXISTS team_pd_direct_lending.mvcontract_details_fact;                  
  DROP MATERIALIZED VIEW IF EXISTS team_pd_direct_lending.mvcontract_summary_fact;                  
  DROP MATERIALIZED VIEW IF EXISTS team_pd_direct_lending.mvportfolio_analytics_fact;               
  DROP MATERIALIZED VIEW IF EXISTS team_pd_direct_lending.mvsecurity_dim;                           
  DROP MATERIALIZED VIEW IF EXISTS team_pd_direct_lending.mvsecurity_master_fact;                   
  DROP MATERIALIZED VIEW IF EXISTS team_pd_direct_lending.mvsecurity_price_fact;                    
  DROP MATERIALIZED VIEW IF EXISTS team_pd_direct_lending.mvsecurity_rating_dim;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_direct_lending.mvtransactions_collateral_exposure_fact;  
  DROP MATERIALIZED VIEW IF EXISTS team_pd_direct_lending.mvtransactions_collateral_positions_fact; 
                                                                                                    
  DROP MATERIALIZED VIEW IF EXISTS team_pd_distressed.mvposition_analytics_fact;                    
  DROP MATERIALIZED VIEW IF EXISTS team_pd_distressed.mvcontract_details_fact;                      
  DROP MATERIALIZED VIEW IF EXISTS team_pd_distressed.mvcontract_summary_fact;                      
  DROP MATERIALIZED VIEW IF EXISTS team_pd_distressed.mvportfolio_analytics_fact;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_distressed.mvsecurity_dim;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_distressed.mvsecurity_master_fact;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_distressed.mvsecurity_price_fact;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_distressed.mvsecurity_rating_dim;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_distressed.mvtransactions_collateral_exposure_fact;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_distressed.mvtransactions_collateral_positions_fact;

  DROP MATERIALIZED VIEW IF EXISTS team_pd_mezzanine.mvposition_analytics_fact;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_mezzanine.mvcontract_details_fact;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_mezzanine.mvcontract_summary_fact;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_mezzanine.mvportfolio_analytics_fact;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_mezzanine.mvsecurity_dim;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_mezzanine.mvsecurity_master_fact;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_mezzanine.mvsecurity_price_fact;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_mezzanine.mvsecurity_rating_dim;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_mezzanine.mvtransactions_collateral_exposure_fact;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_mezzanine.mvtransactions_collateral_positions_fact;

  DROP MATERIALIZED VIEW IF EXISTS team_pd_real_estate_debt.mvposition_analytics_fact;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_real_estate_debt.mvcontract_details_fact;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_real_estate_debt.mvcontract_summary_fact;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_real_estate_debt.mvportfolio_analytics_fact;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_real_estate_debt.mvsecurity_dim;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_real_estate_debt.mvsecurity_master_fact;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_real_estate_debt.mvsecurity_price_fact;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_real_estate_debt.mvsecurity_rating_dim;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_real_estate_debt.mvtransactions_collateral_exposure_fact;
  DROP MATERIALIZED VIEW IF EXISTS
  team_pd_real_estate_debt.mvtransactions_collateral_positions_fact;

  DROP MATERIALIZED VIEW IF EXISTS team_pd_specialty_finance.mvposition_analytics_fact;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_specialty_finance.mvcontract_details_fact;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_specialty_finance.mvcontract_summary_fact;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_specialty_finance.mvportfolio_analytics_fact;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_specialty_finance.mvsecurity_dim;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_specialty_finance.mvsecurity_master_fact;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_specialty_finance.mvsecurity_price_fact;
  DROP MATERIALIZED VIEW IF EXISTS team_pd_specialty_finance.mvsecurity_rating_dim;
  DROP MATERIALIZED VIEW IF EXISTS
  team_pd_specialty_finance.mvtransactions_collateral_exposure_fact;
  DROP MATERIALIZED VIEW IF EXISTS
  team_pd_specialty_finance.mvtransactions_collateral_positions_fact;