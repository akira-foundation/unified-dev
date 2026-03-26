pub mod issue;
pub mod org;
pub mod org_repo;
pub mod provider;

pub use issue::IssueRecord;
pub use org::{OrgRecord, OrgSummary};
pub use org_repo::{OrgRepoSummary, OrgRepoWithOrg};
pub use provider::{ProviderRecord, ProviderSummary};

pub type OrganizationRecord = OrgRecord;
pub type OrganizationSummary = OrgSummary;
pub type OrganizationRepoSummary = OrgRepoSummary;
pub type OrganizationRepoWithOrg = OrgRepoWithOrg;
