from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from routes.auth import router as auth_router
from routes.users import router as users_router
# Import the Household Registration endpoints.
from routes.households import router as households_router
# Import the dashboard endpoints.
from routes.dashboard import router as dashboard_router


app = FastAPI(title="AidTrack API")

# Allow our local Flutter Web app to call the API
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://127.0.0.1:3000",
    ],
    allow_credentials=False,
    allow_methods=["GET", "POST", "PATCH", "DELETE"],
    allow_headers=["Content-Type", "Authorization"],
    # Allow Flutter Web to read the remaining lock time.
    expose_headers=["Retry-After"],
)

app.include_router(auth_router)
app.include_router(users_router)
# Enable the Household Registration endpoints.
app.include_router(households_router)
# Enable the dashboard summary endpoint.
app.include_router(dashboard_router)

@app.get("/")
def root():
    return {"message": "AidTrack API is running"}

@app.get("/health")
def health_check():
    return {"status": "ok"}