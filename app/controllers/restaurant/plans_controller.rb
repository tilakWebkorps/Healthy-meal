class Restaurant::PlansController < ApplicationController
  before_action :get_plan, except: %i[index create]
  def index
    @plans = Plan.includes(days: {meals: [:meal_category, :recipe]}).all
    render json: { plans: show_plans }, status: 200
  end

  def show
    render json: { plan: show_plan }, status: 200
  end

  def create
    @plan = Plan.new(plan_params)
    plan_cost = params[:plan][:plan_cost].to_i
    plan_duration = params[:plan][:plan_duration].to_i
    plan_meals = params[:plan][:plan_meals]
    @errors = {}
    @is_error = false
    check_for_errors(plan_cost, plan_duration, plan_meals)
    return render json: { message: @errors }, status: 406 if @is_error
    if @plan.save
      add_days(plan_meals)
      return render json: { message: @errors }, status: 406 if @is_error
      render json: { message: 'plan created', plan: show_plan }, status: 201
    else
      render json: { message: @plan.errors.messages }, status: 406
    end
  end

  def update
    plan_cost = params[:plan][:plan_cost].to_i
    plan_duration = params[:plan][:plan_duration].to_i
    plan_meals = params[:plan][:plan_meals]
    @errors = {}
    @is_error = false
    check_for_errors(plan_cost, plan_duration, plan_meals)
    return render json: { message: @errors }, status: 406 if @is_error
    if @plan.update(plan_params)
      update_days(plan_meals)
      render json: { message: 'plan updated', plan: show_plan }, status: 200
    else
      render json: { message: @plan.errors.messages }, status: 406
    end
  end

  def buy_plan
    if current_user.active_plan
      render json: { message: 'your plan is already activated try to buy after '+current_user.plan_duration.to_s+' days' }, status: 406
    else
      plan_duration = generate_time(DateTime.now.next_day(@plan.plan_duration))
      user = User.find(current_user.id)
      expiry_date = DateTime.now.next_day(@plan.plan_duration)
      @activate_plan = ActivePlan.create(user_id: current_user.id, plan_id: @plan.id)
      if @activate_plan.save
        if user.update(active_plan: true, plan_duration: plan_duration.to_i, expiry_date: expiry_date)
          render json: { message: generate_bill }
        else
          render json: { message: 'something wrong' }, status: 500
        end
      else
        render json: { message: 'something wrong' }, status: 500
      end
    end
  end

  def destroy
    @plan.destroy
    render json: { message: 'plan deleted' }, status: 200
  end

  private

  def plan_params
    params.require(:plan).permit(:name, :description, :plan_duration, :plan_cost, :image)
  end

  def get_plan
    @plan = Plan.includes(days: {meals: [:meal_category, :recipe]}).find(params[:id])
  end

  def check_for_errors(cost, duration, meals)
    if cost < 1000
      @is_error = true
      @errors[:plan_cost] = 'cost of the plan must be larger than 1000'
    end
    unless [7,14,21].include? duration
      @is_error = true
      @errors[:plan_duration] = 'duration must be 7, 14 or 21'
    end
    unless duration == meals.size
      @is_error = true
      @errors[:plan_meals] = 'please enter all day\'s schedules'
    end
    return @is_error
  end

  def add_days(day_meals)
    for_day = 1
    day_meals.each do |day|
      @day = Day.new(for_day: for_day.to_i, plan_id: @plan.id)
      if @day.save
        add_meal(day)
        for_day += 1
      end
    end
  end

  def add_meal(meals)
    category = 1
    recipes = Recipe.all.ids
    meals.each do |meal, recipe|
      if ['morning_snacks', 'lunch', 'afternoon_snacks', 'dinner', 'hydration'].include?meal
        if recipes.include?recipe
          @meal = Meal.new(day_id: @day.id, meal_category_id: category, recipe_id: recipe.to_i)
          @meal.save
          category += 1
        else
          @is_error = true
          destroy_plan
          @errors[:recipe] = 'the recipe that you give is not found first create it'
        end
      else
        @is_error = true
        destroy_plan
        @errors[:meal] = 'please enter all meal schedule corretly'
      end
    end
  end

  def update_days(plan_meals)
    for_day = 0
    days = @plan.days.sort
    days.each do |day|
      plan_meal = plan_meals[for_day]
      update_meals(day.meals, plan_meal)
      for_day += 1
    end
  end

  def update_meals(meals, plan_meals)
    for_meal = 0
    plan_meals.each do |plan_meal, recipe|
      meal = meals[for_meal]
      meal.recipe_id = recipe.to_i
      meal.save
      for_meal += 1
    end
  end

  def show_plan
    {
      id: @plan.id,
      name: @plan.name,
      description: @plan.description,
      plan_duration: @plan.plan_duration,
      plan_cost: @plan.plan_cost,
      view_url: plan_url(@plan),
      plan_meal: show_plan_day,
      created_at: @plan.created_at,
      updated_at: @plan.updated_at
    }
  end

  def show_plan_day
    plan_meals = []
    @plan.days.each do |day|
      plan_meal = {}
      day.meals.each do |meal|
        plan_meal[meal.meal_category.name] = meal.recipe.name
      end
      plan_meals << plan_meal
    end
    return plan_meals
  end

  def show_plans
    plans = []
    @plans.each do |plan|
      plans << {
        id: plan.id,
        name: plan.name,
        description: plan.description,
        plan_duration: plan.plan_duration,
        plan_cost: plan.plan_cost,
        view_url: plan_url(plan),
        created_at: plan.created_at,
        updated_at: plan.updated_at
      }
    end
    return plans
  end

  def generate_time(time)
    date = ''
    date += time.year.to_s
    date += '0' if time.month.to_i < 10
    date += time.month.to_s
    date += '0' if time.day.to_i < 10
    date += time.day.to_s
    return date
  end

  def generate_bill
    {
      plan_name: @plan.name,
      plan_description: @plan.description,
      plan_cost: @plan.plan_cost,
      plan_duration: @plan.plan_duration,
      expiry_date: "#{current_user.expiry_date.day}/#{current_user.expiry_date.month}/#{current_user.expiry_date.year}"
    }
  end

  def destroy_plan
    @plan.destroy
  end
end