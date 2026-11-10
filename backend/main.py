
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from routes.auth import router as auth_router
from routes.users import router as users_router
from routes.households import router as households_router
from routes.dashboard import router as dashboard_router
from routes.assessments import router as assessments_router
from routes.vulnerability import router as vulnerability_router
from routes.beneficiaries import router as beneficiaries_router
from routes.distributions import router as distributions_router
from routes.reports import router as reports_router


app = FastAPI(title="AidTrack API")


# Allow the local Flutter Web application to access FastAPI.
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://127.0.0.1:3000",
    ],
    allow_credentials=False,
    allow_methods=["GET", "POST", "PATCH", "DELETE"],
    allow_headers=["Content-Type", "Authorization"],
    expose_headers=["Retry-After"],
)


app.include_router(auth_router)
app.include_router(users_router)
app.include_router(households_router)
app.include_router(dashboard_router)
app.include_router(assessments_router)
app.include_router(vulnerability_router)
app.include_router(distributions_router)
app.include_router(reports_router)

# Enable Beneficiary Management endpoints.
app.include_router(beneficiaries_router)


@app.get("/")
def root():
    return {"message": "AidTrack API is running"}


@app.get("/health")
def health_check():
    return {"status": "ok"}
