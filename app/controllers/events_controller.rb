class EventsController < ApplicationController
  def index
    @page = EventListing.new(viewer_id: current_user_id).page(after: params[:after])
  end
end
