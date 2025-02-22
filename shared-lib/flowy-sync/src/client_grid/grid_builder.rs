use crate::errors::{CollaborateError, CollaborateResult};
use flowy_grid_data_model::entities::{BuildGridContext, FieldMeta, GridBlockMeta, GridBlockMetaData, RowMeta};

pub struct GridBuilder {
    build_context: BuildGridContext,
}

impl std::default::Default for GridBuilder {
    fn default() -> Self {
        let mut build_context = BuildGridContext::new();

        let block_meta = GridBlockMeta::new();
        let block_meta_data = GridBlockMetaData {
            block_id: block_meta.block_id.clone(),
            rows: vec![],
        };

        build_context.blocks.push(block_meta);
        build_context.blocks_meta_data.push(block_meta_data);

        GridBuilder { build_context }
    }
}

impl GridBuilder {
    pub fn add_field(mut self, field: FieldMeta) -> Self {
        self.build_context.field_metas.push(field);
        self
    }

    pub fn add_empty_row(mut self) -> Self {
        let row = RowMeta::new(&self.build_context.blocks.first().unwrap().block_id);
        let block_meta = self.build_context.blocks.first_mut().unwrap();
        let block_meta_data = self.build_context.blocks_meta_data.first_mut().unwrap();
        block_meta_data.rows.push(row);
        block_meta.row_count += 1;
        self
    }

    pub fn build(self) -> BuildGridContext {
        self.build_context
    }
}

#[allow(dead_code)]
fn check_rows(fields: &[FieldMeta], rows: &[RowMeta]) -> CollaborateResult<()> {
    let field_ids = fields.iter().map(|field| &field.id).collect::<Vec<&String>>();
    for row in rows {
        let cell_field_ids = row.cells.keys().into_iter().collect::<Vec<&String>>();
        if cell_field_ids != field_ids {
            let msg = format!("{:?} contains invalid cells", row);
            return Err(CollaborateError::internal().context(msg));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {

    use crate::client_grid::{make_block_meta_delta, make_grid_delta, GridBuilder};
    use flowy_grid_data_model::entities::{FieldMeta, FieldType, GridBlockMetaData, GridMeta};

    #[test]
    fn create_default_grid_test() {
        let grid_id = "1".to_owned();
        let build_context = GridBuilder::default()
            .add_field(FieldMeta::new("Name", "", FieldType::RichText, true))
            .add_field(FieldMeta::new("Tags", "", FieldType::SingleSelect, false))
            .add_empty_row()
            .add_empty_row()
            .add_empty_row()
            .build();

        let grid_meta = GridMeta {
            grid_id,
            fields: build_context.field_metas,
            blocks: build_context.blocks,
        };

        let grid_meta_delta = make_grid_delta(&grid_meta);
        let _: GridMeta = serde_json::from_str(&grid_meta_delta.to_str().unwrap()).unwrap();

        let grid_block_meta_delta = make_block_meta_delta(build_context.blocks_meta_data.first().unwrap());
        let _: GridBlockMetaData = serde_json::from_str(&grid_block_meta_delta.to_str().unwrap()).unwrap();
    }
}
