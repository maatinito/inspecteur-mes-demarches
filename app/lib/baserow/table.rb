# frozen_string_literal: true

module Baserow
  class Table
    attr_reader :client, :table_id, :table_name, :fields

    def initialize(client, table_id, table_name = nil)
      @client = client
      @table_id = table_id
      @table_name = table_name
      @fields = {}
      load_fields if table_id
    end

    # Load table information and fields
    def load_fields
      fields_data = client.list_fields(table_id)
      @fields = fields_data.each_with_object({}) do |field, hash|
        hash[field['name']] = {
          id: field['id'],
          type: field['type'],
          primary: field['primary']
        }
      end
    end

    # List all rows in the table
    def list_rows(params = {})
      client.list_rows(table_id, params)
    end

    # Get a specific row by ID
    def get_row(row_id)
      client.get_row(table_id, row_id)
    end

    # Create a new row
    def create_row(data)
      client.create_row(table_id, data)
    end

    # Update an existing row
    def update_row(row_id, data)
      client.update_row(table_id, row_id, data)
    end

    # Delete a row
    def delete_row(row_id)
      client.delete_row(table_id, row_id)
    end

    # Find rows by field value
    def find_by(field_name, value)
      field_id = get_field_id(field_name)
      params = { "filter__field_#{field_id}__equal" => value }
      results = client.list_rows(table_id, params)
      results['results']
    end

    # Search rows by partial text match
    def search(field_name, query)
      field_id = get_field_id(field_name)
      params = { "filter__field_#{field_id}__contains" => query }
      results = client.list_rows(table_id, params)
      results['results']
    end

    # Search rows with human-readable column names using user_field_names parameter
    def search_normalized(field_name, query)
      params = {
        'filters' => {
          'filter_type' => 'AND',
          'filters' => [{
            'field' => field_name,
            'type' => 'contains',
            'value' => query
          }]
        }.to_json,
        'user_field_names' => true
      }
      results = client.list_rows(table_id, params)
      results['results']
    end

    # Find rows with human-readable column names using user_field_names parameter
    def find_by_normalized(field_name, value)
      params = {
        'filters' => {
          'filter_type' => 'AND',
          'filters' => [{
            'field' => field_name,
            'type' => 'equal',
            'value' => value
          }]
        }.to_json,
        'user_field_names' => true
      }
      results = client.list_rows(table_id, params)
      results['results']
    end

    # Get all rows in the table (paginated)
    def all(page = 1, size = 100)
      params = {
        page:,
        size:
      }
      results = client.list_rows(table_id, params)
      results['results']
    end

    private

    # Get the field ID for a given field name
    def get_field_id(field_name)
      field = @fields[field_name]
      return field[:id] if field

      # If fields haven't been loaded yet or field name isn't found, reload fields
      load_fields
      field = @fields[field_name]

      unless field
        available_fields = @fields.keys.join(', ')
        raise ArgumentError, "Field '#{field_name}' not found. Available fields: #{available_fields}"
      end

      field[:id]
    end
  end
end
