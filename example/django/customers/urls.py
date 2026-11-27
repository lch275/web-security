from django.urls import path

from . import views

urlpatterns = [
    path("customers", views.collection),
    path("customers/search", views.search_customers),
    path("customers/contains", views.contains),
    path("customers/sorted", views.sorted_customers),
    path("customers/by-ids", views.by_ids),
    path("customers/batch", views.batch),
    path("customers/<str:customer_id>", views.detail),
]
