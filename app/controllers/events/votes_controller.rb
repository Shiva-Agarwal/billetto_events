module Events
  # Thin controller: parse params, build a command, send it to the command bus.
  class VotesController < ApplicationController
    before_action :require_authentication!
    rate_limit to: 30, within: 1.minute, by: -> { current_user_id }, with: -> { rate_limited }

    rescue_from Command::Invalid, with: :invalid_vote
    rescue_from Voting::EventNotFound, with: :event_not_found

    def create
      command_bus.call(Voting::CastVote.new(event_tid: params[:event_id], user_id: current_user_id, value: params[:value]))
      voted(:recorded)
    end

    def destroy
      command_bus.call(Voting::WithdrawVote.new(event_tid: params[:event_id], user_id: current_user_id))
      voted(:withdrawn)
    end

    private

    def voted(message_key)
      respond_to do |format|
        format.html { redirect_back_or_to root_path, notice: t("votes.#{message_key}"), status: :see_other }
        format.json { render json: { event_tid: params[:event_id], my_vote: my_vote }, status: :ok }
      end
    end

    def my_vote = Voting::Vote.where(event_tid: params[:event_id], user_id: current_user_id).pick(:value)

    def invalid_vote(error)
      respond_to do |format|
        format.html { redirect_back_or_to root_path, alert: error.errors.full_messages.to_sentence, status: :see_other }
        format.json { render json: { error: "invalid", details: error.errors.to_hash }, status: :unprocessable_entity }
      end
    end

    def event_not_found
      respond_to do |format|
        format.html { redirect_to root_path, alert: t("votes.not_found"), status: :see_other }
        format.json { render json: { error: "not_found" }, status: :not_found }
      end
    end

    def rate_limited
      respond_to do |format|
        format.html { redirect_back_or_to root_path, alert: t("votes.rate_limited"), status: :see_other }
        format.json { render json: { error: "rate_limited" }, status: :too_many_requests }
      end
    end
  end
end
