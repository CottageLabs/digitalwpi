# frozen_string_literal: true
class BookmarksController < CatalogController  
  include Blacklight::Bookmarks
  before_action :set_bookmark_category, only: [:index, :action_documents, :update_category_to_bookmark]
  before_action :set_bookmarks, only: :update_category_to_bookmark

  def index    
    @bookmarks = if @bookmark_category.present?
                    token_or_current_or_guest_user.categories.find_by(id: @bookmark_category.id).bookmarks
                else
                  token_or_current_or_guest_user.bookmarks
                end
    bookmark_ids = @bookmarks.collect { |b| b.document_id.to_s }

    @response, @document_list = fetch(bookmark_ids)

    respond_to do |format|
      format.html { }
      format.rss  { render :layout => false }
      format.atom { render :layout => false }
      format.json do
        render json: render_search_results_as_json
      end

      additional_response_formats(format)
      document_export_formats(format)
    end
  end

  def create_category
    if params[:bookmark_category].present?
      bookmark_category = current_user.categories.create(title: params[:bookmark_category])
      if bookmark_category.errors.present?
        flash[:error] = bookmark_category.errors.full_messages
        redirect_to bookmarks_path
      else
        flash[:notice] = "Bookmark Category Created Successfully" 
        redirect_to bookmarks_path
      end
    else
      flash[:error] = "bookmark_category: can't be blank" 
      redirect_to bookmarks_path
    end
  end

  def update_category_to_bookmark
    if @bookmark_category.present? && @bookmarks.present?
      @bookmark_category.bookmarks << @bookmarks
      render json: {massage: "Bookmark added in to Bookmark Category"}, status: 200
    else
      render json: {}, status: 442
    end
  end

  def action_documents
    bookmarks = if params[:bookmark_category_id].present?
                    token_or_current_or_guest_user.categories.find_by(id: params[:bookmark_category_id]).bookmarks
                 else
                  token_or_current_or_guest_user.bookmarks
                 end
    bookmark_ids = bookmarks.collect { |b| b.document_id.to_s }
    fetch(bookmark_ids)
  end

  def generate_share_url
    url_params = {}
    url_params[:encrypted_user_id] = encrypt_user_id(current_user.id) if current_user.present?
    @shareable_url = request.base_url + bookmarks_path(url_params)
    respond_to do |format|
      format.js
    end
  end

  private

  def set_bookmarks
    @bookmarks = current_user.bookmarks.where(document_id: params[:bookmark_document_ids])
  end

  def set_bookmark_category
    begin
      if params[:encrypted_user_id].present?
        category_id = decrypt_bookmark_category_id(params[:encrypted_user_id])
        @bookmark_category = Category.find_by(id: category_id)
      elsif params[:bookmark_category_id].present?
        @bookmark_category = Category.find_by(id: params[:bookmark_category_id])
      end
    rescue Blacklight::Exceptions::ExpiredSessionToken => e
      flash[:error] = "The link you're trying to access has expired"
      redirect_to bookmarks_path
    end 
  end

  def secret_key_generator
    @secret_key_generator ||= begin
      app = Rails.application

      secret_key_base = if app.respond_to?(:credentials)
                          # Rails 5.2+
                          app.credentials.secret_key_base || app.secrets.secret_key_base
                        else
                          # Rails <= 5.1
                          app.secrets.secret_key_base
                        end
      ActiveSupport::KeyGenerator.new(secret_key_base)
    end
  end

  def encrypt_user_id(user_id, current_time = nil)
    current_time ||= Time.zone.now
    message_encryptor.encrypt_and_sign([user_id, current_time, params[:bookmark_category_id]])
  end

  def decrypt_bookmark_category_id(encrypted_user_id)
    user_id, timestamp, bookmark_category_id = message_encryptor.decrypt_and_verify(encrypted_user_id)

    if timestamp < 1.hour.ago
      raise Blacklight::Exceptions::ExpiredSessionToken
    end

    bookmark_category_id
  end
end 