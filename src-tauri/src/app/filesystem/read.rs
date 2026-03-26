use std::fs;
use std::path::Path;

pub async fn read(path: String) -> Result<String, String> {
    let path = Path::new(&path);
    if !path.exists() {
        return Err("File does not exist".to_string());
    }

    fs::read_to_string(path).map_err(|e| e.to_string())
}
