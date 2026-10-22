# frozen_string_literal: true

module EbaySellerApi
  module Resources
    class Tasks < Base
      BASE_PATH = '/sell/feed/v1'
      SCOPE = nil

      def get_order_tasks(params = {})
        get('/order_task', query: params, scope: SELL_FULFILLMENT)
      end

      def create_order_task(data)
        post('/order_task', data, scope: SELL_FULFILLMENT)
      end

      def get_order_task(task_id)
        get("/order_task/#{segment(task_id)}", scope: SELL_FULFILLMENT)
      end

      def get_inventory_tasks(params = {})
        get('/inventory_task', query: params, scope: SELL_INVENTORY)
      end

      def create_inventory_task(data)
        post('/inventory_task', data, scope: SELL_INVENTORY)
      end

      def get_inventory_task(task_id)
        get("/inventory_task/#{segment(task_id)}", scope: SELL_INVENTORY)
      end

      def get_schedules(params = {})
        get('/schedule', query: params)
      end

      def create_schedule(data)
        post('/schedule', data)
      end

      def get_schedule(schedule_id)
        get("/schedule/#{segment(schedule_id)}")
      end

      def update_schedule(schedule_id, data = nil)
        put("/schedule/#{segment(schedule_id)}", data)
      end

      def delete_schedule(schedule_id)
        delete("/schedule/#{segment(schedule_id)}")
      end

      def get_latest_result_file(schedule_id)
        get("/schedule/#{segment(schedule_id)}/download_result_file")
      end

      def get_schedule_template(schedule_template_id)
        get("/schedule_template/#{segment(schedule_template_id)}")
      end

      def get_schedule_templates(params = {})
        get('/schedule_template', query: params)
      end

      def get_tasks(params = {})
        get('/task', query: params)
      end

      def create_task(data)
        post('/task', data)
      end

      def get_input_file(task_id)
        get("/task/#{segment(task_id)}/download_input_file")
      end

      def get_result_file(task_id)
        get("/task/#{segment(task_id)}/download_result_file")
      end

      def get_task(task_id)
        get("/task/#{segment(task_id)}")
      end

      def upload_file(task_id, data = nil)
        post("/task/#{segment(task_id)}/upload_file", data)
      end
    end
  end
end
