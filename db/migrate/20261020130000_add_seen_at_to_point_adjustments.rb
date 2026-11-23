class AddSeenAtToPointAdjustments < ActiveRecord::Migration[8.1]
  def change
    # U12.2: when the member dismissed the pop-up announcing this change. Empty until then.
    add_column :point_adjustments, :seen_at, :datetime
  end
end
