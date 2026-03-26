#[derive(Debug, Clone)]
pub struct VcsCiCheckStep {
    pub number: u64,
    pub name: String,
    pub status: String,
    pub conclusion: Option<String>,
    pub started_at: Option<String>,
    pub completed_at: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct CiCheckStepDto {
    pub number: u64,
    pub name: String,
    pub status: String,
    pub conclusion: Option<String>,
    pub started_at: Option<String>,
    pub completed_at: Option<String>,
}

impl From<VcsCiCheckStep> for CiCheckStepDto {
    fn from(s: VcsCiCheckStep) -> Self {
        Self {
            number: s.number,
            name: s.name,
            status: s.status,
            conclusion: s.conclusion,
            started_at: s.started_at,
            completed_at: s.completed_at,
        }
    }
}

#[derive(Debug, Clone)]
pub struct VcsCiCheck {
    pub id: u64,
    pub name: String,
    pub status: String,
    pub conclusion: Option<String>,
    pub started_at: Option<String>,
    pub completed_at: Option<String>,
    pub steps: Vec<VcsCiCheckStep>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct CiCheckDto {
    pub id: u64,
    pub name: String,
    pub status: String,
    pub conclusion: Option<String>,
    pub started_at: Option<String>,
    pub completed_at: Option<String>,
    pub steps: Vec<CiCheckStepDto>,
}

impl From<VcsCiCheck> for CiCheckDto {
    fn from(c: VcsCiCheck) -> Self {
        Self {
            id: c.id,
            name: c.name,
            status: c.status,
            conclusion: c.conclusion,
            started_at: c.started_at,
            completed_at: c.completed_at,
            steps: c.steps.into_iter().map(CiCheckStepDto::from).collect(),
        }
    }
}
