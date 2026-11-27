from django.urls import include, path

from customers.views import health

urlpatterns = [
    path("health", health),
    path("", include("customers.urls")),
]
